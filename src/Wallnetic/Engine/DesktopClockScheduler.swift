import AppKit

/// One minute-boundary scheduler for every display's clock. It runs only while
/// some display shows a clock: a one-shot timer re-armed for the next boundary,
/// plus an immediate refresh after wake, screen wake, system clock, time zone,
/// day and locale changes. Stopped, it holds no timer and no observer.
final class DesktopClockScheduler {
    /// Schedules `action` at a date and returns a way to cancel it.
    typealias Schedule = (Date, @escaping () -> Void) -> () -> Void

    static let runLoopSchedule: Schedule = { date, action in
        let timer = Timer(fire: date, interval: 0, repeats: false) { _ in action() }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        return { timer.invalidate() }
    }

    private let now: () -> Date
    private let calendar: () -> Calendar
    private let schedule: Schedule
    private let notificationCenter: NotificationCenter
    private let workspaceCenter: NotificationCenter
    private var cancelTimer: (() -> Void)?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var onTick: (() -> Void)?
    private(set) var scheduledFireDate: Date?

    init(now: @escaping () -> Date = Date.init,
         calendar: @escaping () -> Calendar = { .autoupdatingCurrent },
         schedule: @escaping Schedule = DesktopClockScheduler.runLoopSchedule,
         notificationCenter: NotificationCenter = .default,
         workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.now = now
        self.calendar = calendar
        self.schedule = schedule
        self.notificationCenter = notificationCenter
        self.workspaceCenter = workspaceCenter
    }

    deinit { stop() }

    var isRunning: Bool { onTick != nil }
    var observerCount: Int { observers.count }
    var hasPendingTimer: Bool { cancelTimer != nil }

    /// Starts calling `onTick` at every minute boundary after `instant`, the
    /// time the caller just showed; keeps a running schedule and only
    /// replaces the callback.
    func start(from instant: Date, _ onTick: @escaping () -> Void) {
        let wasRunning = isRunning
        self.onTick = onTick
        guard !wasRunning else { return }
        let groups: [(NotificationCenter, [Notification.Name])] = [
            (notificationCenter, [.NSSystemClockDidChange, .NSSystemTimeZoneDidChange, .NSCalendarDayChanged,
                                  NSLocale.currentLocaleDidChangeNotification]),
            (workspaceCenter, [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification]),
        ]
        for (center, names) in groups {
            for name in names {
                let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.refresh()
                }
                observers.append((center, observer))
            }
        }
        arm(after: instant)
    }

    func stop() {
        cancelTimer?()
        cancelTimer = nil
        scheduledFireDate = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        onTick = nil
    }

    /// Updates now and re-arms, so the time shown is current at once.
    func refresh() {
        guard let onTick else { return }
        // Read before the tick draws: arming from a later read would skip a
        // boundary that passed while drawing.
        let instant = now()
        onTick()
        // The tick may have hidden every clock and stopped the schedule.
        guard isRunning else { return }
        arm(after: instant)
    }

    /// A boundary that already passed fires at once and draws the new minute.
    private func arm(after instant: Date) {
        cancelTimer?()
        let fireDate = DesktopClockPolicy.nextMinuteBoundary(after: instant, calendar: calendar())
        scheduledFireDate = fireDate
        cancelTimer = schedule(fireDate) { [weak self] in self?.refresh() }
    }
}
