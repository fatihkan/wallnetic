import SwiftUI
import AppKit

/// Surfaces the underlying `NSWindow` so we can apply title-bar treatments
/// SwiftUI doesn't expose declaratively. Used by Settings and the main
/// window to extend the dark cinematic surface under the traffic lights.
struct WindowChrome: NSViewRepresentable {
    var configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                configure(window)
            }
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
    func cinematicWindowChrome() -> some View {
        background(WindowChrome { window in
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = .clear
            window.isOpaque = false
            // Allow dragging from anywhere in the title-bar region.
            window.isMovableByWindowBackground = false
        })
    }
}
