import Cocoa
import SwiftUI
import Combine

/// Floating Now Playing widget on the desktop.
final class NowPlayingOverlayController: ObservableObject {
    static let shared = NowPlayingOverlayController()

    @AppStorage("nowPlayingOverlay.enabled") var isEnabled: Bool = false
    @AppStorage("nowPlayingOverlay.posX") var posX: Double = -1
    @AppStorage("nowPlayingOverlay.posY") var posY: Double = -1

    @Published var isVisible = false

    private var window: NSPanel?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        if isEnabled {
            DispatchQueue.main.async { [weak self] in self?.show() }
        }
    }

    func show() {
        isEnabled = true
        NowPlayingManager.shared.start()
        openWindow()
    }

    func hide() {
        isEnabled = false
        NowPlayingManager.shared.stop()
        closeWindow()
    }

    func toggle() { isEnabled ? hide() : show() }

    private func openWindow() {
        guard window == nil else { return }
        let size = NSSize(width: 340, height: 92)

        let origin: NSPoint
        if posX >= 0, posY >= 0 {
            origin = NSPoint(x: posX, y: posY)
        } else if let screen = NSScreen.main {
            let f = screen.visibleFrame
            origin = NSPoint(x: f.maxX - size.width - 24, y: f.maxY - size.height - 24)
        } else {
            origin = NSPoint(x: 40, y: 40)
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenNone]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true

        let view = NowPlayingOverlayView()
            .environmentObject(NowPlayingManager.shared)
        panel.contentView = NSHostingView(rootView: view)
        panel.orderFront(nil)

        NotificationCenter.default.addObserver(
            self, selector: #selector(windowMoved(_:)),
            name: NSWindow.didMoveNotification, object: panel
        )

        window = panel
        isVisible = true
    }

    private func closeWindow() {
        NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification, object: window)
        window?.close()
        window = nil
        isVisible = false
    }

    @objc private func windowMoved(_ note: Notification) {
        guard let frame = window?.frame else { return }
        posX = frame.origin.x
        posY = frame.origin.y
    }
}
