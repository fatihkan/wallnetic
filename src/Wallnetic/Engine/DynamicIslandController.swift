import Cocoa
import SwiftUI
import Combine

/// Dynamic Island — wraps around the notch on MacBooks, or floats at top-center on other Macs.
///
/// Multi-monitor: when more than one display is attached, an island is rendered
/// on every monitor and all of them share the same expand/collapse state (driven
/// by `@Published state`, observed by the SwiftUI view).
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

    private var islandWindows: [CGDirectDisplayID: NSPanel] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var autoCollapseTimer: Timer?
    private var screenObserver: NSObjectProtocol?

    // MARK: - Dimensions

    private let compactHeight: CGFloat = 32
    private let expandedWidth: CGFloat = 340
    private let expandedHeight: CGFloat = 130
    private let compactWidth: CGFloat = 290

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

    // MARK: - Show/Hide

    func show() {
        guard islandWindows.isEmpty else { return }
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            islandWindows[id] = makePanel(for: screen)
        }
        hasNotch = NSScreen.screens.contains { detectNotch(for: $0) > 0 }
        isEnabled = true
        isVisible = true
        observeWallpaperChanges()
        observeScreenChanges()
    }

    func hide() {
        autoCollapseTimer?.invalidate()
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
        let hostingView = NSHostingView(
            rootView: DynamicIslandView()
                .environmentObject(WallpaperManager.shared)
                .environmentObject(self)
        )

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenNone]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.contentView = hostingView
        panel.ignoresMouseEvents = false

        panel.orderFront(nil)
        return panel
    }

    // MARK: - State Transitions

    func expand() {
        guard state != .expanded else { return }
        state = .expanded
        updateWindowFrames(animated: true)
        scheduleAutoCollapse()
    }

    func collapse() {
        guard state != .compact, !isRenameActive else { return }
        autoCollapseTimer?.invalidate()
        state = .compact
        updateWindowFrames(animated: true)
    }

    func toggleState() {
        if state == .compact { expand() } else { collapse() }
    }

    func scheduleCollapse() {
        scheduleAutoCollapse()
    }

    private func scheduleAutoCollapse() {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
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
                    context.duration = 0.3
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    panel.animator().setFrame(newFrame, display: true)
                }
            } else {
                panel.setFrame(newFrame, display: true)
            }
        }
    }

    // MARK: - Observers

    private func observeWallpaperChanges() {
        NotificationCenter.default.publisher(for: .wallpaperDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isVisible else { return }
                self.expand()
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

        hasNotch = NSScreen.screens.contains { detectNotch(for: $0) > 0 }
    }
}

// MARK: - NSScreen.displayID

extension NSScreen {
    /// Stable identifier for the underlying display — survives most
    /// topology changes (sleep/wake, resolution toggle). Returns nil
    /// for the rare screen that has no NSScreenNumber device entry.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
