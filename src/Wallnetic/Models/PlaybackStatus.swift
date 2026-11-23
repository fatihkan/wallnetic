import Foundation

enum PlaybackPauseReason: Int, CaseIterable, Equatable {
    // The order is the priority: the first reason present names the pause.
    case manual, calm, thermal, sessionInactive, sleeping, screenSaver, lowPower, battery, lowBattery
    case fullscreen, frontApp, runningApp, idle, otherDisplay, timer

    var title: String {
        switch self {
        case .manual: return String(localized: "Paused by you")
        case .calm: return String(localized: "Paused in Calm Mode")
        case .thermal: return String(localized: "Paused to reduce heat")
        case .sessionInactive: return String(localized: "Paused while the session is locked or inactive")
        case .sleeping: return String(localized: "Paused while the display is asleep")
        case .screenSaver: return String(localized: "Paused for the screen saver")
        case .lowPower: return String(localized: "Paused in Low Power Mode")
        case .battery: return String(localized: "Paused on battery")
        case .lowBattery: return String(localized: "Paused on low battery")
        case .fullscreen: return String(localized: "Paused for a fullscreen app")
        case .frontApp: return String(localized: "Paused for the app in front")
        case .runningApp: return String(localized: "Paused while a chosen app is running")
        case .idle: return String(localized: "Paused while the Mac is idle")
        case .otherDisplay: return String(localized: "Paused while another display is in use")
        case .timer: return String(localized: "Playback timer finished")
        }
    }

    var blocksResume: Bool { self != .manual && self != .timer }

    var condition: String {
        switch self {
        case .manual: return String(localized: "manual pause")
        case .calm: return String(localized: "Calm Mode")
        case .thermal: return String(localized: "thermal pressure or cooling interval")
        case .sessionInactive: return String(localized: "inactive session")
        case .sleeping: return String(localized: "sleeping display")
        case .screenSaver: return String(localized: "screen saver")
        case .lowPower: return String(localized: "Low Power Mode")
        case .battery: return String(localized: "battery policy")
        case .lowBattery: return String(localized: "low battery rule")
        case .fullscreen: return String(localized: "fullscreen app")
        case .frontApp: return String(localized: "app in front rule")
        case .runningApp: return String(localized: "running app rule")
        case .idle: return String(localized: "idle rule")
        case .otherDisplay: return String(localized: "display in use rule")
        case .timer: return String(localized: "finished playback timer")
        }
    }
}

enum RendererPlaybackFailure: Equatable {
    case missingFile, unplayable, loadFailed

    var recovery: String {
        switch self {
        case .missingFile: return String(localized: "The video is missing or inaccessible. Restore the file and retry, or choose another wallpaper.")
        case .unplayable: return String(localized: "This file cannot be played. Choose another video, or retry after replacing it.")
        case .loadFailed: return String(localized: "The video could not be loaded. Retry, or choose another wallpaper.")
        }
    }
}

enum RendererPlaybackState: Equatable {
    case idle, loading, playing, paused, waiting
    case failed(RendererPlaybackFailure)

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// A value snapshot of one display. Intent is separate from the observed
/// player state; requesting Play is not enough to report Playing.
struct DisplayPlaybackStatus: Equatable, Identifiable {
    enum State: Equatable {
        case notSet, loading, playing, waiting, paused
        case unavailable(RendererPlaybackFailure)
    }

    let id: UInt32
    let displayName: String
    let state: State
    let reasons: [PlaybackPauseReason]

    init(id: UInt32, displayName: String, hasWallpaper: Bool,
         renderer: RendererPlaybackState, reasons: [PlaybackPauseReason]) {
        self.id = id
        self.displayName = displayName
        self.reasons = PlaybackPauseReason.allCases.filter { reasons.contains($0) }
        if !hasWallpaper { state = .notSet }
        else if case .failed(let failure) = renderer { state = .unavailable(failure) }
        // A newly enabled policy can precede the actual pause callback. Do
        // not report a stopped player while the observed player is advancing.
        else if renderer == .playing { state = .playing }
        else if !self.reasons.isEmpty { state = .paused }
        else {
            switch renderer {
            case .idle, .loading: state = .loading
            case .playing: state = .playing
            case .waiting: state = .waiting
            case .paused: state = .paused
            case .failed(let failure): state = .unavailable(failure)
            }
        }
    }

    var title: String {
        switch state {
        case .notSet: return String(localized: "No wallpaper selected")
        case .loading: return String(localized: "Loading wallpaper…")
        case .playing: return String(localized: "Playing")
        case .waiting: return String(localized: "Waiting for video")
        case .unavailable: return String(localized: "Wallpaper unavailable")
        case .paused: return reasons.first?.title ?? String(localized: "Paused")
        }
    }

    var detail: String {
        let additional = reasons.dropFirst().map(\.title).joined(separator: ". ")
        let guidance: String
        switch state {
        case .notSet: guidance = "Choose a wallpaper from the library."
        case .unavailable(let failure):
            return ([failure.recovery, String(localized: "A previous wallpaper may remain visible.")] + reasons.map(\.title)).joined(separator: " ")
        case .loading: guidance = "Waiting for the first video frame."
        case .waiting: guidance = "The player is waiting for video data."
        case .playing:
            guard !reasons.isEmpty else { return "" }
            let conditions = reasons.map(\.condition).joined(separator: ", ")
            return String(localized: "Active pause conditions: \(conditions).")
        case .paused:
            let holds = [
                reasons.contains(.calm) ? String(localized: "Turn off Calm Mode to release its hold.") : nil,
                reasons.contains(.thermal) ? String(localized: "The heat hold clears after one minute of cooling, or when thermal-aware playback is turned off.") : nil,
                reasons.contains(.idle) ? String(localized: "Move the pointer or press a key to continue.") : nil,
                reasons.contains(.otherDisplay) ? String(localized: "Use this display to continue here.") : nil
            ].compactMap { $0 }
            let restoration: String
            if reasons.contains(where: \.blocksResume) {
                restoration = reasons.contains(.manual) || reasons.contains(.timer)
                    ? String(localized: "After the active restrictions clear, press Play to resume.")
                    : String(localized: "Playback can resume after the active restrictions clear.")
            } else {
                restoration = String(localized: "Press Play to resume.")
            }
            guidance = (holds + [restoration]).joined(separator: " ")
        }
        return [additional, guidance].filter { !$0.isEmpty }.joined(separator: ". ")
    }

    var canRetry: Bool { if case .unavailable = state { return true }; return false }
    var blocksResume: Bool { reasons.contains(where: \.blocksResume) }
    var symbol: String {
        switch state {
        case .notSet: return "photo"
        case .loading, .waiting: return "hourglass"
        case .playing: return "play.circle"
        case .paused: return "pause.circle"
        case .unavailable: return "exclamationmark.triangle"
        }
    }
}

extension Notification.Name {
    static let playbackRestrictionsDidChange = Notification.Name("playbackRestrictionsDidChange")
}
