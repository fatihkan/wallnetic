import Foundation

enum PlaybackPauseReason: Int, CaseIterable, Equatable {
    case manual, sessionInactive, sleeping, screenSaver, lowPower, battery, fullscreen, covered, timer

    var title: String {
        switch self {
        case .manual: return "Paused by you"
        case .sessionInactive: return "Paused while the session is locked or inactive"
        case .sleeping: return "Paused while the display is asleep"
        case .screenSaver: return "Paused for the screen saver"
        case .lowPower: return "Paused in Low Power Mode"
        case .battery: return "Paused on battery"
        case .fullscreen: return "Paused for a fullscreen app"
        case .covered: return "Paused while the desktop is covered"
        case .timer: return "Playback timer finished"
        }
    }

    var blocksResume: Bool { self != .manual && self != .timer }

    var condition: String {
        switch self {
        case .manual: return "manual pause"
        case .sessionInactive: return "inactive session"
        case .sleeping: return "sleeping display"
        case .screenSaver: return "screen saver"
        case .lowPower: return "Low Power Mode"
        case .battery: return "battery policy"
        case .fullscreen: return "fullscreen app"
        case .covered: return "covered desktop"
        case .timer: return "finished playback timer"
        }
    }
}

enum RendererPlaybackFailure: Equatable {
    case missingFile, unplayable, loadFailed

    var recovery: String {
        switch self {
        case .missingFile: return "The video is missing or inaccessible. Restore the file and retry, or choose another wallpaper."
        case .unplayable: return "This file cannot be played. Choose another video, or retry after replacing it."
        case .loadFailed: return "The video could not be loaded. Retry, or choose another wallpaper."
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
        case .notSet: return "No wallpaper selected"
        case .loading: return "Loading wallpaper…"
        case .playing: return "Playing"
        case .waiting: return "Waiting for video"
        case .unavailable: return "Wallpaper unavailable"
        case .paused: return reasons.first?.title ?? "Paused"
        }
    }

    var detail: String {
        let additional = reasons.dropFirst().map(\.title).joined(separator: ". ")
        let guidance: String
        switch state {
        case .notSet: guidance = "Choose a wallpaper from the library."
        case .unavailable(let failure):
            return ([failure.recovery, "A previous wallpaper may remain visible."] + reasons.map(\.title)).joined(separator: " ")
        case .loading: guidance = "Waiting for the first video frame."
        case .waiting: guidance = "The player is waiting for video data."
        case .playing:
            return reasons.isEmpty ? "" : "Active pause conditions: \(reasons.map(\.condition).joined(separator: ", "))."
        case .paused:
            guidance = reasons.contains(where: \.blocksResume)
                ? "Playback can resume after the active restrictions clear."
                : "Press Play to resume."
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
