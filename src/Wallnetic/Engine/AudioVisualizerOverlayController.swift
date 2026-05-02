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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(layoutDidChange),
            name: .audioVisualizerLayoutDidChange,
            object: nil
        )
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

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: AudioVisualizerManager.shared.sizePreset.dimensions),
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

        anchorPanel(panel)
        panel.orderFront(nil)

        window = panel
        isVisible = true
    }

    /// Computes the panel frame from the current size preset + corner anchor
    /// (#161, #162) and applies it. Called both on `show` and after a layout
    /// notification.
    private func anchorPanel(_ panel: NSPanel) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = AudioVisualizerManager.shared.sizePreset.dimensions
        let inset: CGFloat = 32

        let origin: NSPoint
        switch AudioVisualizerManager.shared.position {
        case .bottomRight:
            origin = NSPoint(x: visible.maxX - size.width - inset, y: visible.minY + inset)
        case .bottomLeft:
            origin = NSPoint(x: visible.minX + inset, y: visible.minY + inset)
        case .topRight:
            origin = NSPoint(x: visible.maxX - size.width - inset, y: visible.maxY - size.height - inset)
        case .topLeft:
            origin = NSPoint(x: visible.minX + inset, y: visible.maxY - size.height - inset)
        case .bottomCenter:
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + inset)
        case .topCenter:
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - inset)
        }

        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
    }

    @objc private func layoutDidChange() {
        guard let panel = window else { return }
        anchorPanel(panel)
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
