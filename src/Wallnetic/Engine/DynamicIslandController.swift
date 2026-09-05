import Cocoa
import SwiftUI
import Combine

/// Dynamic Island — wraps around the notch on MacBooks, or floats at top-center on other Macs.
///
/// Multi-monitor: when more than one display is attached, an island is rendered
/// on every monitor and all of them share the same expand/collapse state (driven
/// by `@Published state`, observed by the SwiftUI view).
///
/// Interaction model: **hover peeks, leaving collapses.** Pointer entry expands;
/// pointer exit collapses after a short grace period so a pointer that skims the
/// edge doesn't flap it. There is deliberately no tap-to-toggle on the surface —
/// on macOS a pointer always hovers before it clicks, so a toggle on tap fought
/// the hover expansion and made clicks look like they did nothing.
class DynamicIslandController: ObservableObject {
    static let shared = DynamicIslandController()

    @AppStorage("island.enabled") var isEnabled: Bool = false

    enum IslandState: Equatable {
        case compact
        case expanded
    }

    @Published var state: IslandState = .compact
    @Published var isVisible = false
    @Published var isRenameActive = false
    @Published var hasNotch = false
    @Published var isDragOver = false
    @Published var isImporting = false
    /// Height of the compact pill. On notch Macs it matches the notch so the
    /// island reads as an extension of it rather than a sticker beneath it.
    @Published private(set) var compactHeight: CGFloat = 32

    private var islandWindows: [CGDirectDisplayID: NSPanel] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var safetyCollapseTimer: Timer?
    private var hoverExitTimer: Timer?
    private var screenObserver: NSObjectProtocol?

    // MARK: - Dimensions

    private let baseCompactHeight: CGFloat = 32
    private let expandedWidth: CGFloat = 340
    private let expandedHeight: CGFloat = 132
    private let compactWidth: CGFloat = 290
    /// Grace after the pointer leaves before collapsing.
    private let hoverExitGrace: TimeInterval = 0.6
    /// Safety net for a hover-exit that is never delivered (window reordering,
    /// Space switch mid-hover). Long enough never to fight someone reading.
    private let safetyCollapseInterval: TimeInterval = 8

    private init() {
        if isEnabled { show() }
    }

    // MARK: - Notch Detection

    private func detectNotch(for screen: NSScreen) -> CGFloat {
        if #available(macOS 12.0, *) {
            return screen.safeAreaInsets.top
        }
        return 0
    }

    private func tallestNotch() -> CGFloat {
        NSScreen.screens.map { detectNotch(for: $0) }.max() ?? 0
    }

    // MARK: - Show/Hide

    func show() {
        guard islandWindows.isEmpty else { return }
        let notch = tallestNotch()
        hasNotch = notch > 0
        compactHeight = hasNotch ? max(baseCompactHeight, notch) : baseCompactHeight
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            islandWindows[id] = makePanel(for: screen)
        }
        isEnabled = true
        isVisible = true
        observeWallpaperChanges()
        observeScreenChanges()
    }

    func hide() {
        safetyCollapseTimer?.invalidate()
        hoverExitTimer?.invalidate()
        cancellables.removeAll()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        for panel in islandWindows.values {
            panel.close()
        }
        islandWindows.removeAll()
        isEnabled = false
        isVisible = false
        state = .compact
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    // MARK: - Panel Factory

    private func makePanel(for screen: NSScreen) -> NSPanel {
        let frame = islandFrame(for: screen, width: compactWidth, height: compactHeight)
        let hostingView = IslandHostingView(
            rootView: DynamicIslandView()
                .environmentObject(WallpaperManager.shared)
                .environmentObject(self)
        )

        // Hover is detected by an AppKit tracking area on this host, not by
        // SwiftUI's onHover — see IslandHostView.
        let host = IslandHostView(controller: self)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: host.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])

        // isReleasedWhenClosed=false (factory) is critical here: an in-flight
        // animator().setFrame (updateWindowFrames) would otherwise over-release
        // the freed panel on the next CA transaction flush. [#206]
        let panel = OverlayWindowFactory.makeOverlayPanel(contentRect: frame, canBecomeKey: true)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        panel.acceptsMouseMovedEvents = true
        // Only take key status when a field asks for it (rename); plain
        // clicks on the controls must not pull focus from the user's app.
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = host

        panel.orderFront(nil)
        return panel
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
        return islandWindows.values.contains { $0.windowNumber == number }
    }

    // MARK: - State Transitions

    func expand() {
        guard state != .expanded else {
            scheduleSafetyCollapse()
            return
        }
        state = .expanded
        updateWindowFrames(animated: true)
        scheduleSafetyCollapse()
    }

    func collapse() {
        guard state != .compact else { return }
        // A rename in progress or a file being dragged over must not be
        // yanked away from under the pointer.
        guard !isRenameActive, !isDragOver else { return }
        safetyCollapseTimer?.invalidate()
        hoverExitTimer?.invalidate()
        state = .compact
        updateWindowFrames(animated: true)
    }

    func toggleState() {
        if state == .compact { expand() } else { collapse() }
    }

    /// Collapse after the hover grace period. Also used by callers that just
    /// finished a modal interaction (rename) and want the island to go away
    /// on its own shortly after.
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

    // MARK: - Window Frame

    private func islandFrame(for screen: NSScreen, width: CGFloat, height: CGFloat) -> NSRect {
        let screenFrame = screen.frame
        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func updateWindowFrames(animated: Bool) {
        let targetWidth = state == .expanded ? expandedWidth : compactWidth
        let targetHeight = state == .expanded ? expandedHeight : compactHeight

        for (id, panel) in islandWindows {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == id }) else { continue }
            let newFrame = islandFrame(for: screen, width: targetWidth, height: targetHeight)

            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.28
                    context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
                    panel.animator().setFrame(newFrame, display: true)
                }
            } else {
                panel.setFrame(newFrame, display: true)
            }
        }
    }

    // MARK: - Observers

    /// Peek open when the *user* changes the wallpaper. Automatic changes —
    /// playlist rotation, time-of-day, weather, launch restore — post the same
    /// notification with `userInitiated: false`, and the island used to pop
    /// open on every one of them, which on a five-minute playlist is a tic.
    private func observeWallpaperChanges() {
        NotificationCenter.default.publisher(for: .wallpaperDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self, self.isVisible else { return }
                let userInitiated = note.userInfo?["userInitiated"] as? Bool ?? true
                guard userInitiated else { return }
                self.expand()
                self.scheduleCollapse()
            }
            .store(in: &cancellables)
    }

    /// Tracks display hot-plug / sleep / mirror toggles. Adds panels for
    /// newly attached screens, drops panels for detached ones, and re-frames
    /// the survivors so anchor math stays correct after a topology change.
    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.screensChanged()
        }
    }

    private func screensChanged() {
        guard isVisible else { return }

        let currentIDs = Set(NSScreen.screens.compactMap { $0.displayID })
        let knownIDs = Set(islandWindows.keys)

        let notch = tallestNotch()
        hasNotch = notch > 0
        compactHeight = hasNotch ? max(baseCompactHeight, notch) : baseCompactHeight

        // Newly attached screens
        for id in currentIDs.subtracting(knownIDs) {
            if let screen = NSScreen.screens.first(where: { $0.displayID == id }) {
                islandWindows[id] = makePanel(for: screen)
            }
        }

        // Detached screens
        for id in knownIDs.subtracting(currentIDs) {
            islandWindows[id]?.close()
            islandWindows.removeValue(forKey: id)
        }

        // Survivors may have moved (mirror on/off, resolution change)
        updateWindowFrames(animated: false)
    }
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
