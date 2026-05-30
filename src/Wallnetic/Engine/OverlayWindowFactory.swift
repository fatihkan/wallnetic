import Cocoa

/// Centralized factory for the app's programmatically-created windows and
/// panels. Every overlay/background window in Wallnetic is owned by ARC
/// (a property or a dictionary on its controller) and torn down with
/// `close()`. The factory bakes in the safe defaults — most importantly
/// `isReleasedWhenClosed = false`, whose per-controller omission caused the
/// #206 unlock crash (a panel freed under an in-flight `_NSWindowTransformAnimation`
/// over-released on the next CoreAnimation flush).
///
/// Keeping the construction in one place means a new overlay can't silently
/// reintroduce that bug class by forgetting a single property.
enum OverlayWindowFactory {

    /// A borderless, non-activating `NSPanel` for floating desktop overlays
    /// (Dynamic Island, Now Playing, controls, audio visualizer).
    ///
    /// - Parameters:
    ///   - contentRect: initial frame.
    ///   - transparent: `true` for clear/transparent overlays (the common
    ///     case); `false` for opaque panels.
    ///   - hasShadow: drop shadow under the panel.
    ///   - clickThrough: when `true` the panel ignores mouse events entirely.
    ///   - movableByBackground: drag-to-move by clicking the panel body.
    static func makeOverlayPanel(
        contentRect: NSRect,
        transparent: Bool = true,
        hasShadow: Bool = false,
        clickThrough: Bool = false,
        movableByBackground: Bool = false
    ) -> NSPanel {
        let panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        // ARC owns the panel via its controller; close() must NOT also
        // release it, or an in-flight animation over-releases freed memory. [#206]
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenNone]
        panel.isOpaque = !transparent
        panel.backgroundColor = transparent ? .clear : .black
        panel.hasShadow = hasShadow
        panel.isMovableByWindowBackground = movableByBackground
        panel.ignoresMouseEvents = clickThrough
        return panel
    }

    /// A borderless `NSWindow` for full-screen background surfaces
    /// (desktop wallpaper layer, lock-screen wallpaper). Opaque by default.
    static func makeBackgroundWindow(
        contentRect: NSRect,
        deferCreation: Bool = true,
        opaque: Bool = true,
        backgroundColor: NSColor = .black
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: deferCreation
        )
        // ARC owns the window via its controller; avoid over-release on close(). [#206]
        window.isReleasedWhenClosed = false
        window.isOpaque = opaque
        window.backgroundColor = backgroundColor
        window.hasShadow = false
        return window
    }
}
