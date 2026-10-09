import AppKit

/// Main-thread scheduling/lifecycle plumbing, disabled for isolated unit tests.
final class WallpaperAutomationRuntime {
    private let observesSystem: Bool
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var callback: (() -> Void)?

    init(observesSystem: Bool = true) { self.observesSystem = observesSystem }
    deinit { stop() }

    func start(_ callback: @escaping () -> Void) {
        stop()
        self.callback = callback
        guard observesSystem else { return }
        let groups: [(NotificationCenter, [Notification.Name])] = [
            (.default, [.NSSystemClockDidChange, .NSSystemTimeZoneDidChange, .NSCalendarDayChanged]),
            (NSWorkspace.shared.notificationCenter, [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification])
        ]
        for (center, names) in groups {
            for name in names {
                let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.callback?() }
                observers.append((center, observer))
            }
        }
    }

    func schedule(after seconds: TimeInterval) {
        timer?.invalidate()
        guard observesSystem, seconds.isFinite else { return }
        let interval = max(0.1, min(60, seconds))
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in self?.callback?() }
        timer.tolerance = min(0.1, interval / 10)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        callback = nil
    }
}

enum WallpaperAutomation {
    static let ownerKey = "wallpaper.automation.owner"

    /// Called after the launch wallpaper restore and playback delegate setup.
    /// If legacy flags conflict, the last chosen owner wins (daily by default).
    static func restore(daily: TimeOfDayManager = .shared, playlist: PlaylistManager = .shared,
                        defaults: UserDefaults = .standard) {
        if daily.isEnabled && playlist.isEnabled {
            if defaults.string(forKey: ownerKey) == "playlist" { daily.stop() }
            else { playlist.stop() }
        }
        if daily.isEnabled { daily.start(restoring: true) }
        else if playlist.isEnabled { playlist.start(restoring: true) }
    }

    static var takesPriorityOverOtherModes: Bool {
        UserDefaults.standard.bool(forKey: "tod.enabled") || UserDefaults.standard.bool(forKey: "playlist.enabled")
    }
}
