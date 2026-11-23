import SwiftUI
import AppKit

/// Surfaces the underlying `NSWindow` so we can apply title-bar treatments
/// SwiftUI doesn't expose declaratively. Main and Settings keep a native
/// title bar so their content never composites over the traffic lights.
struct WindowChrome: NSViewRepresentable {
    var configure: (NSWindow) -> Void
    var onAttach: ((NSWindow) -> Void)? = nil

    func makeNSView(context: Context) -> NSView {
        let view = WindowAwareView(onWindow: configure, onAttach: onAttach)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let aware = nsView as? WindowAwareView {
            aware.onWindow = configure
            aware.onAttach = onAttach
            if let w = nsView.window { configure(w) }
        }
    }

    /// Whether a window with a system toolbar lets its content run under
    /// that toolbar. macOS 26 draws the toolbar as glass over the content;
    /// earlier systems keep the toolbar in a title bar of its own.
    static var toolbarFloatsOverContent: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    static func configureAppWindow(_ window: NSWindow) {
        configureAppWindow(window, hostsToolbar: false)
    }

    /// - Parameters:
    ///   - hostsToolbar: the window has a system toolbar that holds the
    ///     window controls: the main window's tabs, or Settings' sidebar.
    ///   - showsTitle: the title bar names the page (Settings). The main
    ///     window's tabs already say where the user is.
    static func configureAppWindow(_ window: NSWindow, hostsToolbar: Bool, showsTitle: Bool = false) {
        guard window.styleMask.contains(.titled),
              !(window is NSPanel), !window.isSheet else { return }

        window.titleVisibility = showsTitle ? .visible : .hidden
        if hostsToolbar && toolbarFloatsOverContent {
            // The controls sit in the toolbar, which AppKit keeps above the
            // content, and SwiftUI keeps the content's own controls out of
            // the toolbar's safe area. Only backgrounds and scrolled rows
            // pass under the glass.
            window.titlebarAppearsTransparent = true
            // Leave fullscreen's style to AppKit.
            if !window.styleMask.contains(.fullScreen) {
                window.styleMask.insert(.fullSizeContentView)
            }
        } else {
            window.titlebarAppearsTransparent = false
            // #237: use AppKit's reserved title-bar area, not a transparent strip
            // under opaque SwiftUI content. Leave fullscreen's style to AppKit.
            if !window.styleMask.contains(.fullScreen) {
                window.styleMask.remove(.fullSizeContentView)
            }
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
    var onAttach: ((NSWindow) -> Void)?
    private var appearanceObserver: NSObjectProtocol?

    init(onWindow: @escaping (NSWindow) -> Void, onAttach: ((NSWindow) -> Void)?) {
        self.onWindow = onWindow
        self.onAttach = onAttach
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
            onAttach?(w)
            onWindow(w)
        }
    }
}

extension View {
    /// Theme-aware native title bar. Apply only at the main/settings scene root;
    /// sheets, panels and borderless wallpaper windows keep their own chrome.
    func cinematicWindowChrome(isMainWindow: Bool = false, isSettingsWindow: Bool = false,
                               hostsToolbar: Bool? = nil, showsTitle: Bool = false) -> some View {
        let toolbar = hostsToolbar ?? isMainWindow
        let register: ((NSWindow) -> Void)?
        if isMainWindow {
            register = WindowManager.shared.registerMainWindow
        } else if isSettingsWindow {
            register = WindowManager.shared.registerSettingsWindow
        } else {
            register = nil
        }
        return background(WindowChrome(
            configure: { WindowChrome.configureAppWindow($0, hostsToolbar: toolbar, showsTitle: showsTitle) },
            onAttach: register))
    }
}
