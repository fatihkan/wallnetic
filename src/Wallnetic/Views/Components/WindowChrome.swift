import SwiftUI
import AppKit

/// Surfaces the underlying `NSWindow` so we can apply title-bar treatments
/// SwiftUI doesn't expose declaratively. Main and Settings keep a native
/// title bar so their content never composites over the traffic lights.
struct WindowChrome: NSViewRepresentable {
    var configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowAwareView(onWindow: configure)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let aware = nsView as? WindowAwareView {
            aware.onWindow = configure
            if let w = nsView.window { configure(w) }
        }
    }

    static func configureAppWindow(_ window: NSWindow) {
        guard window.styleMask.contains(.titled),
              !(window is NSPanel), !window.isSheet else { return }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        // #237: use AppKit's reserved title-bar area, not a transparent strip
        // under opaque SwiftUI content. Leave fullscreen's style to AppKit.
        if !window.styleMask.contains(.fullScreen) {
            window.styleMask.remove(.fullSizeContentView)
        }
        window.appearance = ThemeManager.shared.appearanceMode.nsAppearance
        window.isOpaque = true
        window.backgroundColor = NSColor(Surface.stageFloor)
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(type)?.isHidden = false
        }
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
    }
}

/// NSView that fires its callback the moment it's attached to a window,
/// and again whenever the app appearance changes — so an already-mounted
/// chrome view picks up Light/Dark toggles without recreating the scene.
private final class WindowAwareView: NSView {
    var onWindow: ((NSWindow) -> Void)
    private var appearanceObserver: NSObjectProtocol?

    init(onWindow: @escaping (NSWindow) -> Void) {
        self.onWindow = onWindow
        super.init(frame: .zero)
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: .appAppearanceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let w = self.window else { return }
            self.onWindow(w)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let w = window {
            // Promote on attachment, before initial title-bar composition.
            // Do not do this in updateNSView: hidden windows still receive
            // SwiftUI updates and must not undo Hide Dock icon on every update.
            if w.styleMask.contains(.titled), !(w is NSPanel), !w.isSheet,
               NSApp.activationPolicy() == .accessory {
                NSApp.setActivationPolicy(.regular)
            }
            onWindow(w)
        }
    }
}

extension View {
    /// Theme-aware native title bar. Apply only at the main/settings scene root;
    /// sheets, panels and borderless wallpaper windows keep their own chrome.
    func cinematicWindowChrome() -> some View {
        background(WindowChrome(configure: WindowChrome.configureAppWindow))
    }
}
