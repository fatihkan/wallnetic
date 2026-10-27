import AppKit
import Combine

/// Shows one clock per display in that display's wallpaper window (#311),
/// from values only: the display id, whether its window shows a presented
/// frame, and its pause reasons. It holds no reference to renderers,
/// `PauseAfterPlayback` or `PowerManager`, never changes playback, and never
/// orders, reveals or changes a window.
final class DesktopClockCoordinator {
    struct Display: Equatable {
        let id: CGDirectDisplayID
        let hasPresentedFrame: Bool
        let reasons: [PlaybackPauseReason]
    }

    /// A display's frame, visible frame and backing scale. Read when drawing,
    /// so Dock and menu-bar changes apply by the next minute at the latest.
    struct Geometry: Equatable {
        let frame: CGRect
        let visibleFrame: CGRect
        let scale: CGFloat
    }

    private let settings: DesktopClockSettings
    private let scheduler: DesktopClockScheduler
    private let now: () -> Date
    private let locale: () -> Locale
    private let timeZone: () -> TimeZone
    private let geometry: (CGDirectDisplayID) -> Geometry?
    private let wantsBackdrop: () -> Bool
    private var preferences: DesktopClockSettings.Preferences
    private var views: [CGDirectDisplayID: DesktopClockView] = [:]
    private var displays: [Display] = []
    private var settingsObserver: AnyCancellable?
    /// Backing-scale and contrast changes, observed only while a clock shows.
    private var changeObservers: [(NotificationCenter, NSObjectProtocol)] = []

    init(settings: DesktopClockSettings = .shared,
         scheduler: DesktopClockScheduler = DesktopClockScheduler(),
         now: @escaping () -> Date = Date.init,
         locale: @escaping () -> Locale = { .autoupdatingCurrent },
         timeZone: @escaping () -> TimeZone = { .autoupdatingCurrent },
         geometry: @escaping (CGDirectDisplayID) -> Geometry? = DesktopClockCoordinator.screenGeometry,
         wantsBackdrop: @escaping () -> Bool = DesktopClockCoordinator.accessibilityWantsBackdrop) {
        self.settings = settings
        self.scheduler = scheduler
        self.now = now
        self.locale = locale
        self.timeZone = timeZone
        self.geometry = geometry
        self.wantsBackdrop = wantsBackdrop
        preferences = settings.preferences
        // `@Published` emits before it stores, so use the emitted value.
        settingsObserver = settings.$preferences.dropFirst().sink { [weak self] next in
            self?.preferences = next
            self?.refresh()
        }
    }

    static func screenGeometry(_ id: CGDirectDisplayID) -> Geometry? {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == id }) else { return nil }
        return Geometry(frame: screen.frame, visibleFrame: screen.visibleFrame, scale: screen.backingScaleFactor)
    }

    static func accessibilityWantsBackdrop() -> Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    var isScheduling: Bool { scheduler.isRunning }
    var isObservingChanges: Bool { !changeObservers.isEmpty }

    func view(for id: CGDirectDisplayID) -> DesktopClockView? { views[id] }

    /// A clock view for a display, to be added last to its wallpaper window's
    /// content, as a sibling of the renderer view.
    func makeView(for id: CGDirectDisplayID, frame: NSRect) -> NSView {
        let view = DesktopClockView(frame: frame)
        view.autoresizingMask = [.width, .height]
        views[id] = view
        return view
    }

    func removeView(for id: CGDirectDisplayID) {
        views.removeValue(forKey: id)?.removeFromSuperview()
        displays.removeAll { $0.id == id }
        refresh()
    }

    /// The latest state of every display; shows, hides and schedules.
    func update(_ displays: [Display]) {
        self.displays = displays
        refresh()
    }

    func cleanup() {
        settingsObserver = nil
        scheduler.stop()
        stopObservingChanges()
        views.values.forEach { $0.hide() }
        views.removeAll()
        displays.removeAll()
    }

    private func refresh() {
        var text: (time: String, date: String?)?
        var anyVisible = false
        for (id, view) in views {
            guard isVisible(id), let geometry = geometry(id) else {
                view.hide()
                continue
            }
            // Formatted once per refresh, for every display that shows it.
            let shown = text ?? format(now())
            text = shown
            view.show(content(time: shown.time, date: shown.date, geometry: geometry))
            anyVisible = true
        }
        if anyVisible {
            scheduler.start { [weak self] in self?.refresh() }
            observeChanges()
        } else {
            scheduler.stop()
            stopObservingChanges()
        }
    }

    private func isVisible(_ id: CGDirectDisplayID) -> Bool {
        guard let display = displays.first(where: { $0.id == id }) else { return false }
        return DesktopClockPolicy.isVisible(enabled: preferences.showClock, hasPresentedFrame: display.hasPresentedFrame,
                                            reasons: display.reasons)
    }

    private func format(_ date: Date) -> (time: String, date: String?) {
        let locale = locale(), timeZone = timeZone()
        return (DesktopClockFormat.time(date, locale: locale, timeZone: timeZone),
                preferences.showDate ? DesktopClockFormat.date(date, locale: locale, timeZone: timeZone) : nil)
    }

    private func content(time: String, date: String?, geometry: Geometry) -> DesktopClockView.Content {
        let visible = DesktopClockLayout.visibleRect(screenFrame: geometry.frame, visibleFrame: geometry.visibleFrame)
        return DesktopClockView.Content(
            time: time, date: date,
            fontSize: max(12, (visible.height * CGFloat(preferences.size.timeFraction)).rounded()),
            position: preferences.position, visibleRect: visible, scale: geometry.scale, backdrop: wantsBackdrop())
    }

    private func observeChanges() {
        guard changeObservers.isEmpty else { return }
        let refresh: (Notification) -> Void = { [weak self] _ in self?.refresh() }
        changeObservers = [
            (NotificationCenter.default, NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeBackingPropertiesNotification, object: nil, queue: .main, using: refresh)),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main,
                using: refresh)),
        ]
    }

    private func stopObservingChanges() {
        for (center, observer) in changeObservers { center.removeObserver(observer) }
        changeObservers.removeAll()
    }
}
