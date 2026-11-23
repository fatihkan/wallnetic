import Cocoa
import SwiftUI
import Combine

/// Dynamic Island (#352): a shape that hangs from the screen's top edge. On
/// a MacBook it flows out of the notch; on any other display it is a bar of
/// its own in the middle of the menu bar.
///
/// Every display gets its own island with its own geometry, and all of them
/// share the same compact or expanded state.
///
/// Interaction model: **hover peeks, leaving collapses.** Pointer entry expands;
/// pointer exit collapses after a short grace period so a pointer that skims the
/// edge doesn't flap it. There is deliberately no tap-to-toggle on the surface —
/// on macOS a pointer always hovers before it clicks, so a toggle on tap fought
/// the hover expansion and made clicks look like they did nothing.
///
/// The shape is drawn by `IslandSurfaceView`. A timer drives the spring only
/// while the shape moves; a resting island draws nothing.
class DynamicIslandController: ObservableObject {
    static let shared = DynamicIslandController()

    @AppStorage("island.enabled") var isEnabled: Bool = false

    enum IslandState: Equatable {
        case compact
        case expanded
    }

    @Published var state: IslandState = .compact
    @Published var isVisible = false
    @Published var isDragOver = false
    @Published var isImporting = false
    /// True when Metal is not usable. The view then draws a plain shape.
    @Published private(set) var drawsPlainShape = false

    private struct Island {
        let panel: NSPanel
        let surface: IslandSurfaceView
        /// The view that holds the thumbnail, the text and the controls.
        let content: NSView
        /// Cuts the content to the shape, so nothing shows outside it.
        let clip: CAShapeLayer
        /// The size of `surface` and `content`: the expanded window's size.
        let contentSize: CGSize
        let metrics: IslandMetrics
        /// The island's top centre in screen coordinates.
        let anchor: CGPoint
    }

    private var islands: [CGDirectDisplayID: Island] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var safetyCollapseTimer: Timer?
    private var hoverExitTimer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    private var morph = IslandSpring()
    private var morphTimer: Timer?
    private var lastTick: CFTimeInterval = 0
    private var style = IslandStyle()
    /// Looking at a state without a pointer, in debug builds only.
    private var staysExpanded = false
    private var debugCycleTimer: Timer?

    /// Grace after the pointer leaves before collapsing.
    private let hoverExitGrace: TimeInterval = 0.6
    /// Safety net for a hover-exit that is never delivered (window reordering,
    /// Space switch mid-hover). Long enough never to fight someone reading.
    private let safetyCollapseInterval: TimeInterval = 8

    private init() {
        if isEnabled { show() }
    }

    // MARK: - Displays

    /// The notch of a display, or none, and its menu bar's height.
    /// `safeAreaInsets` gives the notch's height and the two areas beside it
    /// give its width.
    static func metrics(for screen: NSScreen, defaults: UserDefaults = .standard) -> IslandMetrics {
        let menuBar = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        #if DEBUG
        // A notch to look at on a Mac without one:
        // -island.debugNotchWidth 200 -island.debugNotchHeight 32
        let debugWidth = defaults.double(forKey: "island.debugNotchWidth")
        let debugHeight = defaults.double(forKey: "island.debugNotchHeight")
        if debugWidth > 0, debugHeight > 0 {
            return IslandMetrics(notch: CGSize(width: debugWidth, height: debugHeight), menuBarHeight: menuBar)
        }
        #endif
        let height = screen.safeAreaInsets.top
        guard height > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else {
            return IslandMetrics(menuBarHeight: menuBar)
        }
        let width = screen.frame.width - left.width - right.width
        guard width > 0 else { return IslandMetrics(menuBarHeight: menuBar) }
        return IslandMetrics(notch: CGSize(width: width, height: height), menuBarHeight: menuBar)
    }

    private var reducesMotion: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "island.debugReduceMotion") { return true }
        #endif
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var increasesContrast: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "island.debugIncreaseContrast") { return true }
        #endif
        return NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    // MARK: - Show/Hide

    func show() {
        guard islands.isEmpty else { return }
        refreshStyle()
        makeIslands()
        isEnabled = true
        isVisible = true
        observeWallpaperChanges()
        observeEnvironment()
        applyVisibility()
        #if DEBUG
        applyDebugState()
        #endif
    }

    func hide() {
        stopTimers()
        cancellables.removeAll()
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        closeIslands()
        isEnabled = false
        isVisible = false
        state = .compact
        morph = IslandSpring()
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    private func stopTimers() {
        safetyCollapseTimer?.invalidate()
        hoverExitTimer?.invalidate()
        debugCycleTimer?.invalidate()
        morphTimer?.invalidate()
        morphTimer = nil
    }

    private func makeIslands() {
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            islands[id] = makeIsland(for: screen)
        }
        drawsPlainShape = islands.values.contains { !$0.surface.isAvailable }
        applyShape()
    }

    private func closeIslands() {
        for island in islands.values { island.panel.close() }
        islands.removeAll()
    }

    // MARK: - Panel Factory

    private func makeIsland(for screen: NSScreen) -> Island {
        let metrics = Self.metrics(for: screen)
        let anchor = IslandGeometry.anchor(screenFrame: screen.frame)
        let frame = IslandGeometry.windowFrame(expanded: state == .expanded, metrics: metrics, anchor: anchor)

        let surface = IslandSurfaceView()
        let hostingView = IslandHostingView(
            rootView: DynamicIslandView(metrics: metrics, displayName: screen.localizedName)
                .environmentObject(WallpaperManager.shared)
                .environmentObject(self)
        )
        // The controller sizes the window. SwiftUI's ideal size must not.
        hostingView.sizingOptions = []
        // While the shape grows or shrinks, the content is cut to it: a
        // control that is still fading must not hang out of a smaller shape.
        hostingView.wantsLayer = true
        let clip = CAShapeLayer()
        clip.fillColor = NSColor.black.cgColor
        hostingView.layer?.mask = clip

        // Hover is detected by an AppKit tracking area on this host, not by
        // SwiftUI's onHover — see IslandHostView.
        let host = IslandHostView(controller: self)
        // The surface and the content always have the expanded window's size
        // and hang from the window's top centre. When the window changes
        // size, AppKit only moves them, in the same pass: nothing is drawn
        // again and nothing is laid out again. Sized to the window, the
        // surface once kept a frame of the old size, stretched, and the
        // content sat beside the shape until SwiftUI caught up.
        let full = IslandGeometry.windowFrame(expanded: true, metrics: metrics, anchor: anchor).size
        for view in [surface, hostingView] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(view)
            NSLayoutConstraint.activate([
                view.centerXAnchor.constraint(equalTo: host.centerXAnchor),
                view.topAnchor.constraint(equalTo: host.topAnchor),
                view.widthAnchor.constraint(equalToConstant: full.width),
                view.heightAnchor.constraint(equalToConstant: full.height),
            ])
        }

        // isReleasedWhenClosed=false (factory) keeps a closed panel alive for
        // anything still in flight on the next CA transaction flush. [#206]
        let panel = OverlayWindowFactory.makeOverlayPanel(contentRect: frame, canBecomeKey: true)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        panel.acceptsMouseMovedEvents = true
        // Clicks on the controls must not pull focus from the user's app.
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = host
        return Island(panel: panel, surface: surface, content: hostingView, clip: clip, contentSize: full,
                      metrics: metrics, anchor: anchor)
    }

    // MARK: - Pointer

    func pointerEntered() {
        hoverExitTimer?.invalidate()
        hoverExitTimer = nil
        expand()
    }

    /// The tracking area is rebuilt on every resize (i.e. every expand), and
    /// AppKit delivers spurious exits during it while the cursor never left —
    /// and can miss the real one. So exits are treated as a hint only; the
    /// grace timer re-asks the window server where the cursor actually is
    /// before collapsing.
    func pointerExited() {
        guard state == .expanded else { return }
        scheduleCollapse()
    }

    /// Authoritative: asks the window server which window is under the cursor.
    private func cursorIsOverIsland() -> Bool {
        let number = NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
        return islands.values.contains { $0.panel.windowNumber == number }
    }

    // MARK: - State Transitions

    func expand() {
        guard state != .expanded else {
            scheduleSafetyCollapse()
            return
        }
        state = .expanded
        morph.target = 1
        // The window takes its full size first; the shape then stretches
        // inside it.
        applyFrames()
        startMorph()
        scheduleSafetyCollapse()
    }

    func collapse() {
        guard state != .compact else { return }
        // A file being dragged over must not lose its target.
        guard !isDragOver, !staysExpanded else { return }
        safetyCollapseTimer?.invalidate()
        hoverExitTimer?.invalidate()
        state = .compact
        morph.target = 0
        startMorph()
    }

    func toggleState() {
        if state == .compact { expand() } else { collapse() }
    }

    /// Collapse after the hover grace period. Also used by callers that want
    /// the island to go away on its own shortly after a peek.
    func scheduleCollapse() {
        hoverExitTimer?.invalidate()
        hoverExitTimer = Timer.scheduledTimer(withTimeInterval: hoverExitGrace, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                // Still hovering? The exit was noise — check again later.
                if self.cursorIsOverIsland() {
                    self.scheduleCollapse()
                    return
                }
                self.collapse()
            }
        }
    }

    private func scheduleSafetyCollapse() {
        safetyCollapseTimer?.invalidate()
        safetyCollapseTimer = Timer.scheduledTimer(withTimeInterval: safetyCollapseInterval, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.collapse() }
        }
    }

    // MARK: - Morph

    /// Runs the spring until it rests. The timer exists only while the shape
    /// moves.
    private func startMorph() {
        guard morphTimer == nil else { return }
        lastTick = CACurrentMediaTime()
        let rate = max(60, NSScreen.screens.map(\.maximumFramesPerSecond).max() ?? 60)
        let timer = Timer(timeInterval: 1.0 / Double(rate), repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        morphTimer = timer
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let elapsed = CGFloat(now - lastTick)
        lastTick = now
        if reducesMotion {
            morph.fade(by: elapsed)
            if morph.value == morph.target { morph.settle() }
        } else {
            morph.advance(by: elapsed)
        }
        applyShape()
        guard morph.isSettled else { return }
        morphTimer?.invalidate()
        morphTimer = nil
        // After a collapse the window shrinks back around the compact shape.
        applyFrames()
    }

    /// A window is as large as the expanded shape while the island is open or
    /// moving, and as small as the compact shape while it rests. The window
    /// never animates: only the shape inside it does.
    private func applyFrames() {
        let expanded = state == .expanded || !morph.isSettled
        for island in islands.values {
            let frame = IslandGeometry.windowFrame(expanded: expanded, metrics: island.metrics,
                                                   anchor: island.anchor)
            if island.panel.frame != frame { island.panel.setFrame(frame, display: true) }
        }
    }

    private func applyShape() {
        let crossFades = reducesMotion
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for island in islands.values {
            let shape = IslandGeometry.layout(progress: morph.value, metrics: island.metrics,
                                              crossFades: crossFades)
            island.surface.show(shape, style: style)
            island.clip.path = Self.clipPath(for: shape, size: island.contentSize, flipped: island.content.isFlipped)
        }
        CATransaction.commit()
    }

    /// The card's outline in the content view's coordinates. Its top reaches
    /// above the view, so only the lower corners are rounded.
    static func clipPath(for shape: IslandLayout, size: CGSize, flipped: Bool) -> CGPath {
        let card = shape.card
        let radius = min(shape.cardRadius, card.width / 2)
        let height = card.maxY + radius
        let rect = CGRect(x: size.width / 2 + card.minX,
                          y: flipped ? -radius : size.height - card.maxY,
                          width: card.width, height: height)
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    /// The glow follows the wallpaper's colour. Increase Contrast replaces it
    /// with a solid fill and an outline.
    private func refreshStyle() {
        // The accent lives on the main actor. Callers are on the main thread
        // already; the hop gives the compiler the isolation it wants.
        Task { @MainActor [weak self] in
            guard let self else { return }
            var next = IslandStyle()
            let theme = DynamicAccent.shared.theme
            if let colour = NSColor(theme.primary).usingColorSpace(.sRGB) {
                next.glow = SIMD3(Float(colour.redComponent), Float(colour.greenComponent),
                                  Float(colour.blueComponent))
            }
            next.glowStrength = Float(0.35 + 0.35 * theme.glow)
            next.increasesContrast = self.increasesContrast
            self.style = next
            self.applyShape()
        }
    }

    /// The island steps aside while an app is in full screen.
    private func applyVisibility() {
        let shown = IslandPolicy.isShown(enabled: isVisible,
                                         fullscreenAppActive: PowerManager.shared.isFullscreenAppActive)
        for island in islands.values {
            if shown { island.panel.orderFront(nil) } else { island.panel.orderOut(nil) }
        }
        if !shown, state == .expanded, !staysExpanded {
            isDragOver = false
            collapse()
        }
    }

    // MARK: - Observers

    /// Peek open when the *user* changes the wallpaper. Automatic changes —
    /// playlist rotation, time-of-day, weather, launch restore — post the same
    /// notification with `userInitiated: false`, and an island that opened on
    /// every one of them would be a tic. It also stays closed while the user
    /// is typing.
    private func observeWallpaperChanges() {
        NotificationCenter.default.publisher(for: .wallpaperDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self, self.isVisible else { return }
                let userInitiated = note.userInfo?["userInitiated"] as? Bool ?? true
                let sinceKey = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
                guard userInitiated, IslandPolicy.mayOpenUnasked(secondsSinceLastKey: sinceKey) else { return }
                self.expand()
                self.scheduleCollapse()
            }
            .store(in: &cancellables)
    }

    private func observeEnvironment() {
        Task { @MainActor [weak self] in
            guard let self, self.isVisible else { return }
            DynamicAccent.shared.$theme
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refreshStyle() }
                .store(in: &self.cancellables)
        }

        NotificationCenter.default.publisher(for: .playbackRestrictionsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyVisibility() }
            .store(in: &cancellables)

        // Display hot-plug, sleep, mirroring and resolution changes move the
        // notch and the menu bar, so every island is made again.
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.screensChanged()
        }
        // Increase Contrast and Reduce Motion.
        observe(NSWorkspace.shared.notificationCenter,
                NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { [weak self] in
            self?.refreshStyle()
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping () -> Void) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }
        observers.append((center, observer))
    }

    private func screensChanged() {
        guard isVisible else { return }
        closeIslands()
        makeIslands()
        applyVisibility()
    }

    // MARK: - Debug

    #if DEBUG
    /// States to look at without a pointer:
    /// `-island.debugExpanded YES` keeps the island open,
    /// `-island.debugProgress 0.5` holds the shape between the two states, and
    /// `-island.debugCycle YES` opens and closes it every two seconds.
    /// `-island.debugReduceMotion YES` and `-island.debugIncreaseContrast YES`
    /// stand in for the two system settings.
    private func applyDebugState() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "island.debugCycle") {
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.toggleState() }
            RunLoop.main.add(timer, forMode: .common)
            debugCycleTimer = timer
        }
        if defaults.bool(forKey: "island.debugExpanded") {
            staysExpanded = true
            expand()
            safetyCollapseTimer?.invalidate()
        }
        if defaults.object(forKey: "island.debugProgress") != nil {
            staysExpanded = true
            stopTimers()
            state = .expanded
            morph.target = CGFloat(defaults.double(forKey: "island.debugProgress"))
            morph.settle()
            applyFrames()
            applyShape()
        }
    }
    #endif
}

// MARK: - Hover host

/// Hover detection that actually works for a non-activating panel.
///
/// SwiftUI's `onHover` rides an NSTrackingArea scoped to the key window, and
/// this panel is never key — so in the shipped app, hovering the island did
/// nothing at all and only the tap (which fought the hover) responded.
/// `.activeAlways` is AppKit's answer: enter/exit are delivered regardless of
/// key or active state.
private final class IslandHostView: NSView {
    private weak var controller: DynamicIslandController?
    private var tracking: NSTrackingArea?

    init(controller: DynamicIslandController) {
        self.controller = controller
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { controller?.pointerEntered() }

    override func mouseExited(with event: NSEvent) { controller?.pointerExited() }
}

/// Hosting view that accepts the first mouse click. Without this, the first
/// click on a control in a non-key panel is consumed to make the window key
/// and never reaches the SwiftUI Button — every island button needed two
/// clicks, and the first one looked like it did nothing.
private final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// NSScreen.displayID moved to Utils/NSScreen+DisplayID.swift (now shared
// by DesktopWindowController and SystemWallpaperSync for stable per-display
// keying).
