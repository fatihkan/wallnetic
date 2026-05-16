import SwiftUI

/// A soft accent halo that follows keyboard focus. Apple's 2026 design
/// adds a literal glow around the focused interactive element (whatever
/// the user would activate if they hit ⏎). Apply via `.focusHalo()` on
/// any view paired with `@FocusState`.
///
/// We don't reuse SwiftUI's `.focused()` glow because the system version
/// is too subtle on dark cinematic surfaces — easy to lose focus state.
struct FocusHalo: ViewModifier {
    let isFocused: Bool
    let radius: CGFloat
    var accent: Color = .accentColor

    @Environment(\.accentTheme) private var accentTheme

    func body(content: Content) -> some View {
        let color = (accent == .accentColor) ? accentTheme.primary : accent

        content
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(color.opacity(isFocused ? 0.85 : 0), lineWidth: isFocused ? 1.5 : 0)
                    .blur(radius: 0.4)
            )
            .shadow(color: color.opacity(isFocused ? 0.55 : 0), radius: isFocused ? 16 : 0)
            .shadow(color: color.opacity(isFocused ? 0.30 : 0), radius: isFocused ? 4 : 0)
            .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}

extension View {
    func focusHalo(_ isFocused: Bool, radius: CGFloat = Radius.control, accent: Color = .accentColor) -> some View {
        modifier(FocusHalo(isFocused: isFocused, radius: radius, accent: accent))
    }

    /// Suppresses macOS's system focus ring (the thick pink/blue rounded
    /// rectangle that appears around a focused Button). Use on custom
    /// list/sidebar rows whose selection is already indicated visually.
    /// No-op on macOS < 14.
    @ViewBuilder
    func suppressFocusRing() -> some View {
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled()
        } else {
            self
        }
    }
}
