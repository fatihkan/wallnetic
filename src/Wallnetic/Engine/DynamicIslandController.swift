import Cocoa
import SwiftUI
import Combine

/// Dynamic Island — wraps around the notch on MacBooks, or floats at top-center on other Macs
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

    private var islandWindow: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private var autoCollapseTimer: Timer?

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
        guard islandWindow == nil else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        hasNotch = detectNotch(for: screen) > 0

        let content = DynamicIslandView()
            .environmentObject(WallpaperManager.shared)
            .environmentObject(self)

        let hostingView = NSHostingView(rootView: content)
        let frame = islandFrame(for: screen, width: compactWidth, height: compactHeight)

        let window = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenNone]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = false
        window.contentView = hostingView
        window.ignoresMouseEvents = false

        window.orderFront(nil)
        islandWindow = window
        isEnabled = true
        isVisible = true
        observeWallpaperChanges()
    }

    func hide() {
        autoCollapseTimer?.invalidate()
        cancellables.removeAll()
        islandWindow?.close()
        islandWindow = nil
        isEnabled = false
        isVisible = false
        state = .compact
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    // MARK: - State Transitions

    func expand() {
        guard state != .expanded else { return }
        state = .expanded
        updateWindowFrame(animated: true)
        scheduleAutoCollapse()
    }

    func collapse() {
        guard state != .compact, !isRenameActive else { return }
        autoCollapseTimer?.invalidate()
        state = .compact
        updateWindowFrame(animated: true)
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

    private func updateWindowFrame(animated: Bool) {
        guard let window = islandWindow, let screen = NSScreen.main else { return }
        let targetWidth = state == .expanded ? expandedWidth : compactWidth
        let targetHeight = state == .expanded ? expandedHeight : compactHeight
        let newFrame = islandFrame(for: screen, width: targetWidth, height: targetHeight)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(newFrame, display: true)
            }
        } else {
            window.setFrame(newFrame, display: true)
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
}
