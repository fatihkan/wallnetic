import SwiftUI

// MARK: - Adaptive glass (#343 B3)
//
// macOS 26 draws real Liquid Glass with `glassEffect()`. Earlier systems
// have no such API, so a surface keeps the background it had before: a
// material, or the `LiquidGlass` polyfill.
//
// Use these on custom surfaces only. The window toolbar, sheets, menus,
// alerts and standard controls take their glass from the system, and glass
// is never stacked on glass.

extension View {
    /// Liquid Glass in `shape` on macOS 26. On macOS 13–25 the view gets
    /// `fallback` as its background, which is what the surface drew before.
    @ViewBuilder
    func adaptiveGlass<S: Shape, Fallback: View>(
        in shape: S,
        @ViewBuilder fallback: () -> Fallback
    ) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(fallback())
        }
    }

    /// Liquid Glass on macOS 26, and the `LiquidGlass` polyfill panel with
    /// its strokes and shadow on macOS 13–25.
    @ViewBuilder
    func adaptiveGlass(polyfill style: LiquidGlassStyle) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: RoundedRectangle(cornerRadius: style.radius, style: .continuous))
        } else {
            liquidGlass(style)
        }
    }

    /// For the content of a system sheet. macOS 26 draws the sheet itself as
    /// glass, so the content adds no panel of its own there. Earlier systems
    /// keep the polyfill panel.
    @ViewBuilder
    func sheetSurface(polyfill style: LiquidGlassStyle) -> some View {
        if #available(macOS 26.0, *) {
            self
        } else {
            liquidGlass(style)
        }
    }
}
