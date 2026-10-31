import Foundation

/// Main-thread playback ownership for per-display duration pauses. A timer
/// pause preserves playback intent; an explicit Pause revokes it until Play.
final class PauseAfterPlayback {
    private struct Entry {
        let renderer: WallpaperRenderer
        let url: URL
        var duration: TimeInterval?
        var startedAt: TimeInterval?
        var expired = false
    }

    private var entries: [UInt32: Entry] = [:]
    private let now: () -> TimeInterval
    private let canPlay: () -> Bool
    private(set) var isRequested = false
    private(set) var isManuallyPaused = false
    private(set) var holds: Set<PlaybackHold> = []
    private var heldAt: TimeInterval?
    var onChange: (() -> Void)?

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         canPlay: @escaping () -> Bool) {
        self.now = now
        self.canPlay = canPlay
    }

    var hasActivePlayback: Bool { isRequested && holds.isEmpty && entries.values.contains { !$0.expired } }
    var isPausedAfterDuration: Bool { isRequested && !entries.isEmpty && entries.values.allSatisfy { $0.expired } }
    var needsTimer: Bool {
        isRequested && holds.isEmpty && entries.values.contains {
            !$0.expired && $0.duration != nil && $0.renderer.playbackMonitor.hasFrameForCurrentLoad
        }
    }
    var hasTimedWallpapers: Bool { entries.values.contains { $0.duration != nil } }

    func shouldPlay(on display: UInt32) -> Bool {
        isRequested && holds.isEmpty && canPlay() && entries[display].map { !$0.expired } == true
    }

    func isExpired(on display: UInt32) -> Bool { entries[display]?.expired == true }

    func setWallpaper(_ url: URL, renderer: WallpaperRenderer, on display: UInt32,
                      preferences: PauseAfterSettings.Preferences) {
        entries[display] = Entry(renderer: renderer, url: url, duration: preferences.duration(for: url))
        if shouldPlay(on: display) { renderer.play() }
        onChange?()
    }

    /// Holds stop motion without revoking the user's intent or expiring/restarting
    /// per-display timers. Removing one hold cannot release another one.
    func setHolds(_ next: Set<PlaybackHold>) {
        guard next != holds else { return }
        let wasHeld = !holds.isEmpty
        holds = next
        if !holds.isEmpty {
            if !wasHeld {
                heldAt = now()
                for entry in entries.values { entry.renderer.pause() }
            }
        } else {
            if let heldAt {
                let elapsed = max(0, now() - heldAt)
                for id in Array(entries.keys) {
                    if let started = entries[id]?.startedAt { entries[id]?.startedAt = started + elapsed }
                }
            }
            heldAt = nil
            for (id, entry) in entries where shouldPlay(on: id) { entry.renderer.play() }
        }
        onChange?()
    }

    /// Automatic wallpaper changes keep other displays' deadlines. Explicit
    /// Play, or a permitted resume after a power pause, starts fresh intervals.
    func play(explicit: Bool = false) {
        guard canPlay() else { return }
        if explicit { isManuallyPaused = false }
        guard !isManuallyPaused else { return }
        let restart = explicit || !isRequested
        isRequested = true
        for id in Array(entries.keys) {
            if restart {
                entries[id]?.startedAt = nil
                entries[id]?.expired = false
            }
            if let entry = entries[id], shouldPlay(on: id) { entry.renderer.play() }
        }
        tick()
        onChange?()
    }

    func pause(manual: Bool) {
        if manual { isManuallyPaused = true }
        isRequested = false
        for entry in entries.values { entry.renderer.pause() }
        onChange?()
    }

    func updatePreferences(_ preferences: PauseAfterSettings.Preferences) {
        for id in Array(entries.keys) {
            guard var entry = entries[id] else { continue }
            let duration = preferences.duration(for: entry.url)
            guard entry.duration != duration else { continue }
            entry.duration = duration
            entry.startedAt = nil
            entry.expired = false
            entries[id] = entry
            if shouldPlay(on: id) { entry.renderer.play() }
        }
        tick()
        onChange?()
    }

    func tick() {
        guard isRequested && holds.isEmpty && canPlay() else { return }
        let time = now()
        guard time.isFinite else { return }
        var changed = false
        for id in Array(entries.keys) {
            guard var entry = entries[id], !entry.expired,
                  let duration = entry.duration, entry.renderer.hasPresentedFrame,
                  entry.renderer.playbackMonitor.hasFrameForCurrentLoad else { continue }
            // A retained frame can belong to the previous wallpaper. Only the
            // selected video's first frame may start its playback interval.
            if entry.startedAt == nil { entry.startedAt = time }
            if time - (entry.startedAt ?? time) >= duration {
                entry.expired = true
                entry.renderer.pause()
                changed = true
            }
            entries[id] = entry
        }
        if changed { onChange?() }
    }

    func replayExpiredDisplay(_ display: UInt32) {
        guard isRequested, holds.isEmpty, !isManuallyPaused, canPlay(), entries[display]?.expired == true else { return }
        entries[display]?.expired = false
        entries[display]?.startedAt = nil
        entries[display]?.renderer.play()
        tick()
        onChange?()
    }

    func remove(_ display: UInt32) {
        entries.removeValue(forKey: display)
        onChange?()
    }

    func removeAll() {
        entries.removeAll()
        isRequested = false
        onChange?()
    }
}
