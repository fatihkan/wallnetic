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
    /// Font sizes fitted to a visible area, by everything the widest text
    /// depends on, so the clock keeps its size as the time and date change.
    private var fittedFontSizes: [FitKey: CGFloat] = [:]

    /// What one refresh shows, and the locale it comes from.
    private struct Text {
        let time: String
        let date: String?
        let locale: Locale
    }

    private struct FitKey: Hashable {
        let width: CGFloat
        let height: CGFloat
        let requested: CGFloat
        let backdrop: Bool
        let locale: String
        let showsDate: Bool
    }

    init(settings: DesktopClockSettings = .shared,
         scheduler: DesktopClockScheduler = DesktopClockScheduler(),
         now: @escaping () -> Date = Date.init,
         locale: @escaping () -> Locale = { DesktopClockFormat.systemLocale() },
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
        fittedFontSizes.removeAll()
    }

    private func refresh() {
        // One read per refresh: the text and the next boundary come from it.
        let instant = now()
        var text: Text?
        var anyVisible = false
        for (id, view) in views {
            guard isVisible(id), let geometry = geometry(id) else {
                view.hide()
                continue
            }
            // Formatted once per refresh, for every display that shows it.
            let shown = text ?? format(instant)
            text = shown
            view.show(content(shown, geometry: geometry))
            anyVisible = true
        }
        if anyVisible {
            scheduler.start(from: instant) { [weak self] in self?.refresh() }
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

    private func format(_ date: Date) -> Text {
        let locale = locale(), timeZone = timeZone()
        return Text(time: DesktopClockFormat.time(date, locale: locale, timeZone: timeZone),
                    date: preferences.showDate ? DesktopClockFormat.date(date, locale: locale, timeZone: timeZone) : nil,
                    locale: locale)
    }

    private func content(_ text: Text, geometry: Geometry) -> DesktopClockView.Content {
        let visible = DesktopClockLayout.visibleRect(screenFrame: geometry.frame, visibleFrame: geometry.visibleFrame)
        var content = DesktopClockView.Content(
            time: text.time, date: text.date,
            fontSize: max(12, (visible.height * CGFloat(preferences.size.timeFraction)).rounded()),
            position: preferences.position, visibleRect: visible, scale: geometry.scale, backdrop: wantsBackdrop())
        content.fontSize = fittedFontSize(for: content, locale: text.locale)
        return content
    }

    /// The largest font, up to the chosen size, at which the widest time and
    /// date of this locale fit the visible area.
    private func fittedFontSize(for content: DesktopClockView.Content, locale: Locale) -> CGFloat {
        let key = FitKey(width: content.visibleRect.width, height: content.visibleRect.height,
                         requested: content.fontSize, backdrop: content.backdrop, locale: locale.identifier,
                         showsDate: content.date != nil)
        if let fontSize = fittedFontSizes[key] { return fontSize }
        let samples = DesktopClockFormat.samples(locale: locale)
        let widest = DesktopClockView.widest(times: samples.times + [content.time],
                                             dates: samples.dates + (content.date.map { [$0] } ?? []),
                                             fontSize: content.fontSize)
        var measured = content
        measured.time = widest.time
        measured.date = content.date == nil ? nil : widest.date
        let fontSize = DesktopClockLayout.fittedFontSize(content.fontSize, in: content.visibleRect) { fontSize in
            measured.fontSize = fontSize
            return DesktopClockView.image(for: measured).size
        }
        // Areas and settings change rarely; this only bounds a long session.
        if fittedFontSizes.count >= 64 { fittedFontSizes.removeAll() }
        fittedFontSizes[key] = fontSize
        return fontSize
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
