import Cocoa
import SwiftUI

/// Click-through audio visualizer overlay anchored at the bottom of the
/// active screen.
final class AudioVisualizerOverlayController: ObservableObject {
    static let shared = AudioVisualizerOverlayController()

    @AppStorage("audioVisualizer.overlayEnabled") var isEnabled: Bool = false

    @Published var isVisible = false
    private var window: NSPanel?

    private init() {
        if isEnabled {
            DispatchQueue.main.async { [weak self] in self?.show() }
        }
    }

    func show() {
        guard window == nil else { return }
        isEnabled = true
        AudioVisualizerManager.shared.start()

        // If the manager couldn't start (no input device, tap threw, permission
        // denied) disable the overlay so we don't auto-launch into the same
        // crash on the next run.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            if !AudioVisualizerManager.shared.isRunning {
                self.hide()
                return
            }
        }

        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 300, height: 300)
        let origin = NSPoint(
            x: screenFrame.maxX - size.width - 32,
            y: screenFrame.minY + 32
        )

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
        panel.hasShadow = false
        panel.ignoresMouseEvents = true  // click-through

        panel.contentView = NSHostingView(
            rootView: AudioVisualizerOverlayView()
                .environmentObject(AudioVisualizerManager.shared)
        )
        panel.orderFront(nil)

        window = panel
        isVisible = true
    }

    func hide() {
        isEnabled = false
        AudioVisualizerManager.shared.stop()
        window?.close()
        window = nil
        isVisible = false
    }

    func toggle() { isVisible ? hide() : show() }
}
