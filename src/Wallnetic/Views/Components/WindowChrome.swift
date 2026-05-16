import SwiftUI
import AppKit

/// Surfaces the underlying `NSWindow` so we can apply title-bar treatments
/// SwiftUI doesn't expose declaratively. Used by Settings and the main
/// window to extend the dark cinematic surface under the traffic lights.
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
            onWindow(w)
        }
    }
}

extension View {
    /// Applies Wallnetic's cinematic-dark title-bar treatment:
    ///  - hidden title text
    ///  - transparent titlebar so content extends underneath
    ///  - full-size content view (no reserved title-bar strip)
    ///  - forced dark appearance
    ///  - clear NSWindow bg so the SwiftUI ambient stage shows through
    ///
    /// **Apply at scene root only.** If the view is hosted in a
    /// non-`.titled` NSWindow (popover, sheet, panel, menu) the call
    /// short-circuits to avoid corrupting unrelated chrome. M3 guard.
    func cinematicWindowChrome() -> some View {
        background(WindowChrome { window in
            // M3: skip popovers/sheets/panels — they have their own chrome
            // and don't carry traffic lights, so applying these flags
            // would either be a no-op or break their layout.
            guard window.styleMask.contains(.titled) else { return }

            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            // Theme-aware: nil means "follow NSApp.appearance / system",
            // so System/Light/Dark from Settings actually takes effect.
            // WindowAwareView listens for .appAppearanceDidChange and
            // re-runs this closure when the user toggles.
            window.appearance = ThemeManager.shared.appearanceMode.nsAppearance
            window.backgroundColor = .clear
            window.isOpaque = false
            // Remove the hairline that macOS otherwise draws between the
            // title-bar zone and content — we have our own design.
            window.titlebarSeparatorStyle = .none
            window.isMovableByWindowBackground = false
        })
    }
}
