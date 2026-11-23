import Foundation

/// An app the user chose for a playback rule.
struct PlaybackRuleApp: Codable, Hashable, Identifiable {
    let bundleID: String
    let name: String

    var id: String { bundleID }
}

/// The optional playback rules (#350). Every rule is off by default and
/// works on its own.
struct PlaybackRulesConfiguration: Codable, Equatable {
    /// Pause while one of `frontApps` is the frontmost app.
    var pausesForFrontApps = false
    var frontApps: [PlaybackRuleApp] = []
    /// Pause while one of `runningApps` is running.
    var pausesForRunningApps = false
    var runningApps: [PlaybackRuleApp] = []
    /// Pause after the keyboard, mouse and trackpad have been left alone
    /// for `idleMinutes`.
    var pausesWhenIdle = false
    var idleMinutes = 5
    /// Pause on battery below `lowBatteryPercent`.
    var pausesOnLowBattery = false
    var lowBatteryPercent = 20
    /// With several displays, play only where the pointer or the active
    /// window is.
    var playsOnlyOnDisplayInUse = false

    static let idleMinuteChoices = [1, 2, 5, 10, 15, 30]
    static let batteryPercentChoices = [10, 20, 30, 40, 50]

    init() {}

    /// Missing keys keep their defaults, so a later version can add a rule
    /// without losing the saved ones.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? values.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        pausesForFrontApps = value(.pausesForFrontApps, false)
        frontApps = value(.frontApps, [])
        pausesForRunningApps = value(.pausesForRunningApps, false)
        runningApps = value(.runningApps, [])
        pausesWhenIdle = value(.pausesWhenIdle, false)
        idleMinutes = max(1, value(.idleMinutes, 5))
        pausesOnLowBattery = value(.pausesOnLowBattery, false)
        lowBatteryPercent = min(100, max(1, value(.lowBatteryPercent, 20)))
        playsOnlyOnDisplayInUse = value(.playsOnlyOnDisplayInUse, false)
    }

    /// True when a rule needs a value that no notification announces: idle
    /// time, the battery level, or where the pointer is.
    var needsSampling: Bool { pausesWhenIdle || pausesOnLowBattery || playsOnlyOnDisplayInUse }
    var isAnyRuleOn: Bool { pausesForFrontApps || pausesForRunningApps || needsSampling }
}

/// What the rules look at, read with public APIs that ask for no permission.
struct PlaybackRulesEnvironment: Equatable {
    var frontmostBundleID: String?
    var runningBundleIDs: Set<String> = []
    /// Seconds since the last keyboard, mouse or trackpad event.
    var idleSeconds: TimeInterval = 0
    var isOnBattery = false
    /// Nil on a Mac without a battery.
    var batteryPercent: Int?
    /// The displays that show a wallpaper.
    var displays: [UInt32] = []
    /// The displays that have the pointer or the active window right now.
    var displaysInUse: Set<UInt32> = []
}

/// Pure decisions for the playback rules. A rule that applies becomes a
/// hold: it stops motion without touching the user's own Play or Pause, and
/// releasing it never releases another hold or a manual pause.
enum PlaybackRules {
    /// How long a display counts as in use after the pointer or the active
    /// window left it, so crossing between displays does not flicker.
    static let displayGrace: TimeInterval = 10

    static func holds(_ rules: PlaybackRulesConfiguration,
                      _ environment: PlaybackRulesEnvironment) -> Set<PlaybackHold> {
        var holds: Set<PlaybackHold> = []
        if rules.pausesForFrontApps, let front = environment.frontmostBundleID,
           rules.frontApps.contains(where: { $0.bundleID == front }) {
            holds.insert(.frontApp)
        }
        if rules.pausesForRunningApps,
           rules.runningApps.contains(where: { environment.runningBundleIDs.contains($0.bundleID) }) {
            holds.insert(.runningApp)
        }
        if rules.pausesWhenIdle, environment.idleSeconds.isFinite,
           environment.idleSeconds >= TimeInterval(rules.idleMinutes * 60) {
            holds.insert(.idle)
        }
        if rules.pausesOnLowBattery, environment.isOnBattery,
           let percent = environment.batteryPercent, percent < rules.lowBatteryPercent {
            holds.insert(.lowBattery)
        }
        return holds
    }

    /// The displays to pause for "play only on the display in use".
    ///
    /// - Parameter lastUsed: when each display last had the pointer or the
    ///   active window, in the same clock as `now`.
    /// - Returns: empty with the rule off, with one display, or while no
    ///   display is known to be in use, so playback never stops everywhere.
    static func inactiveDisplays(_ rules: PlaybackRulesConfiguration, displays: [UInt32],
                                 lastUsed: [UInt32: TimeInterval], now: TimeInterval,
                                 grace: TimeInterval = displayGrace) -> Set<UInt32> {
        guard rules.playsOnlyOnDisplayInUse, displays.count > 1, now.isFinite else { return [] }
        let inUse = displays.filter { id in
            guard let used = lastUsed[id] else { return false }
            return now - used <= grace
        }
        guard !inUse.isEmpty else { return [] }
        return Set(displays).subtracting(inUse)
    }

    /// How often the sampled values are read, or nil when no rule needs
    /// sampling. An idle hold is watched closely so input resumes at once.
    static func samplingInterval(_ rules: PlaybackRulesConfiguration, holds: Set<PlaybackHold>) -> TimeInterval? {
        guard rules.needsSampling else { return nil }
        if rules.pausesWhenIdle && holds.contains(.idle) { return 0.5 }
        if rules.pausesWhenIdle || rules.playsOnlyOnDisplayInUse { return 2 }
        return 30
    }
}
