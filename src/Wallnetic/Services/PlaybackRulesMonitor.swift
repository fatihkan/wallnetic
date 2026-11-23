import AppKit
import Combine
import IOKit.ps

/// Watches what the playback rules depend on and publishes the holds that
/// apply (#350). Main-thread only.
///
/// It uses public APIs that ask for no permission: `NSWorkspace` for the
/// frontmost and running apps, `CGEventSource` for idle time, IOKit power
/// sources for the battery, and the pointer and window list for the display
/// in use. It never plays or pauses anything itself.
final class PlaybackRulesMonitor: ObservableObject {
    static let shared = PlaybackRulesMonitor()

    @Published private(set) var holds: Set<PlaybackHold> = []
    /// Displays paused by "play only on the display in use".
    @Published private(set) var inactiveDisplays: Set<UInt32> = []

    private let settings: PlaybackRulesSettings
    private let sample: (PlaybackRulesConfiguration) -> PlaybackRulesEnvironment
    private let now: () -> TimeInterval
    private var lastUsed: [UInt32: TimeInterval] = [:]
    private var timer: Timer?
    private var timerInterval: TimeInterval?
    private var observers: [NSObjectProtocol] = []
    private var settingsObserver: AnyCancellable?

    init(settings: PlaybackRulesSettings = .shared,
         sample: @escaping (PlaybackRulesConfiguration) -> PlaybackRulesEnvironment = PlaybackRulesMonitor.currentEnvironment,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         observesSystem: Bool = true) {
        self.settings = settings
        self.sample = sample
        self.now = now
        if observesSystem {
            let workspace = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didActivateApplicationNotification,
                         NSWorkspace.didLaunchApplicationNotification,
                         NSWorkspace.didTerminateApplicationNotification] {
                observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.refresh()
                })
            }
            // Posted when the power source changes, among other restrictions.
            observers.append(NotificationCenter.default.addObserver(
                forName: .playbackRestrictionsDidChange, object: nil, queue: .main) { [weak self] _ in
                    self?.refresh()
            })
        }
        // `@Published` emits before it stores, so refresh with the new rules.
        settingsObserver = settings.$rules.dropFirst().sink { [weak self] rules in
            self?.refresh(rules: rules)
        }
        refresh()
    }

    deinit {
        timer?.invalidate()
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func refresh() { refresh(rules: settings.rules) }

    private func refresh(rules: PlaybackRulesConfiguration) {
        guard rules.isAnyRuleOn else {
            lastUsed.removeAll()
            publish(holds: [], inactiveDisplays: [])
            schedule(nil)
            return
        }
        let environment = sample(rules)
        let time = now()
        if rules.playsOnlyOnDisplayInUse {
            // A display that just appeared counts as in use, so the rule
            // never pauses one before the user has had a chance to use it.
            for id in environment.displays where lastUsed[id] == nil { lastUsed[id] = time }
            for id in environment.displaysInUse { lastUsed[id] = time }
            lastUsed = lastUsed.filter { environment.displays.contains($0.key) }
        } else {
            lastUsed.removeAll()
        }
        let nextHolds = PlaybackRules.holds(rules, environment)
        publish(holds: nextHolds,
                inactiveDisplays: PlaybackRules.inactiveDisplays(rules, displays: environment.displays,
                                                                 lastUsed: lastUsed, now: time))
        schedule(PlaybackRules.samplingInterval(rules, holds: nextHolds))
    }

    private func publish(holds next: Set<PlaybackHold>, inactiveDisplays nextDisplays: Set<UInt32>) {
        if next != holds { holds = next }
        if nextDisplays != inactiveDisplays { inactiveDisplays = nextDisplays }
    }

    private func schedule(_ interval: TimeInterval?) {
        guard interval != timerInterval else { return }
        timer?.invalidate()
        timer = nil
        timerInterval = interval
        guard let interval else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Reading the system

    /// Reads only what the rules that are on need.
    static func currentEnvironment(_ rules: PlaybackRulesConfiguration) -> PlaybackRulesEnvironment {
        var environment = PlaybackRulesEnvironment()
        let workspace = NSWorkspace.shared
        if rules.pausesForFrontApps {
            environment.frontmostBundleID = workspace.frontmostApplication?.bundleIdentifier
        }
        if rules.pausesForRunningApps {
            environment.runningBundleIDs = Set(workspace.runningApplications.compactMap(\.bundleIdentifier))
        }
        if rules.pausesWhenIdle {
            // Every input event type; asks for no permission.
            let anyInput = CGEventType(rawValue: ~0) ?? .null
            environment.idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                                              eventType: anyInput)
        }
        if rules.pausesOnLowBattery {
            let battery = batteryState()
            environment.isOnBattery = battery.isOnBattery
            environment.batteryPercent = battery.percent
        }
        if rules.playsOnlyOnDisplayInUse {
            environment.displays = NSScreen.screens.compactMap(\.displayID)
            environment.displaysInUse = displaysInUse(frontmost: workspace.frontmostApplication?.processIdentifier)
        }
        return environment
    }

    static func batteryState() -> (isOnBattery: Bool, percent: Int?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return (false, nil)
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let onBattery = description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
            return (onBattery, Int((Double(current) / Double(maximum) * 100).rounded()))
        }
        return (false, nil)
    }

    /// The display under the pointer, and the display that holds the
    /// frontmost app's frontmost window. Window bounds and owners are
    /// readable without the Screen Recording permission.
    static func displaysInUse(frontmost pid: pid_t?) -> Set<UInt32> {
        var result: Set<UInt32> = []
        let pointer = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }),
           let id = screen.displayID {
            result.insert(id)
        }
        guard let pid,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return result }
        // The list is front to back, so the first match is the active window.
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let boundsValue = window[kCGWindowBounds as String],
                  let bounds = CGRect(dictionaryRepresentation: boundsValue as! CFDictionary),
                  bounds.width > 0, bounds.height > 0 else { continue }
            var display: CGDirectDisplayID = 0
            var count: UInt32 = 0
            if CGGetDisplaysWithPoint(CGPoint(x: bounds.midX, y: bounds.midY), 1, &display, &count) == .success,
               count > 0 {
                result.insert(display)
            }
            break
        }
        return result
    }
}
