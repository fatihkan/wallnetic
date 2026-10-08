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
    var onChange: (() -> Void)?

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         canPlay: @escaping () -> Bool) {
        self.now = now
        self.canPlay = canPlay
    }

    var hasActivePlayback: Bool { isRequested && entries.values.contains { !$0.expired } }
    var isPausedAfterDuration: Bool { isRequested && !entries.isEmpty && !hasActivePlayback }
    var needsTimer: Bool { isRequested && entries.values.contains { !$0.expired && $0.duration != nil } }
    var hasTimedWallpapers: Bool { entries.values.contains { $0.duration != nil } }

    func shouldPlay(on display: UInt32) -> Bool {
        isRequested && entries[display].map { !$0.expired } == true
    }

    func isExpired(on display: UInt32) -> Bool { entries[display]?.expired == true }

    func setWallpaper(_ url: URL, renderer: WallpaperRenderer, on display: UInt32,
                      preferences: PauseAfterSettings.Preferences) {
        entries[display] = Entry(renderer: renderer, url: url, duration: preferences.duration(for: url))
        if isRequested && canPlay() { renderer.play() }
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
            if let entry = entries[id], !entry.expired { entry.renderer.play() }
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
            if isRequested && canPlay() { entry.renderer.play() }
        }
        tick()
        onChange?()
    }

    func tick() {
        guard isRequested && canPlay() else { return }
        let time = now()
        guard time.isFinite else { return }
        var changed = false
        for id in Array(entries.keys) {
            guard var entry = entries[id], !entry.expired,
                  let duration = entry.duration, entry.renderer.hasPresentedFrame else { continue }
            // Never freeze an empty overlay while its first video is loading.
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
        guard isRequested, !isManuallyPaused, canPlay(), entries[display]?.expired == true else { return }
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
