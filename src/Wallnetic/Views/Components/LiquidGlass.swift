import SwiftUI

// MARK: - Liquid Glass Material (2026 polyfill)
//
// Captures the visual language of macOS 26's "Liquid Glass" without the
// `glassEffect()` API (which requires macOS 26+, while we target macOS 13+).
//
// The illusion is built from four stable layers:
//   1. `.regularMaterial` — content blur (the actual translucent base)
//   2. **Accent tint** — a soft overlay that pulls the chrome toward the
//      current accent color (acts like the refractive color cast of glass
//      bending light from underlying content)
//   3. **Lensing strokes** — bright top-inner stroke + dim bottom-inner
//      stroke, simulating how real glass catches and absorbs light
//   4. **Multi-layer shadow** — close ambient + far drop, gives the panel
//      real spatial depth
//
// Always paired with a `.continuous`-style RoundedRectangle so the shape
// language stays squircle.

struct LiquidGlassStyle {
    var radius: CGFloat = Radius.panel
    var accent: Color = .accentColor
    var accentStrength: Double = 0.10       // 0 = pure neutral glass, 1 = strong tint
    var tone: Tone = .standard

    enum Tone {
        /// Default — slightly darker than ultraThin; sits over content.
        case standard
        /// Floating chrome (toolbars, HUDs) — denser, more legible.
        case prominent
        /// Inline controls (buttons, chips) — thin, accent-led.
        case control
    }

    fileprivate var baseFill: Color {
        switch tone {
        case .standard:  return Surface.glassStandard
        case .prominent: return Surface.glassProminent
        case .control:   return Surface.glassControl
        }
    }

    fileprivate var topStroke: Color { Surface.glassTopStroke }
    fileprivate var bottomStroke: Color { Surface.glassBottomStroke }
    fileprivate var innerHighlight: Color { Surface.glassInnerHighlight }
    fileprivate var ambientShadow: Color {
        switch tone {
        case .prominent: return Color.adaptive(dark: .black.opacity(0.35), light: .black.opacity(0.12))
        case .standard:  return Color.adaptive(dark: .black.opacity(0.25), light: .black.opacity(0.08))
        case .control:   return Color.adaptive(dark: .black.opacity(0.15), light: .black.opacity(0.05))
        }
    }

    fileprivate var dropShadow: Color { accent.opacity(0.22 * accentStrength + 0.10) }
}

extension View {
    /// Wraps the view in a Liquid Glass panel.
    func liquidGlass(_ style: LiquidGlassStyle = LiquidGlassStyle()) -> some View {
        modifier(LiquidGlassModifier(style: style))
    }
}

private struct LiquidGlassModifier: ViewModifier {
    let style: LiquidGlassStyle

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // 1) Material blur — only for prominent/standard tones.
                    // P2-8: .control tone skips material to avoid stacking
                    // 3+ blur passes per window (TopNav + Sidebar + Sheet
                    // already each carry one).
                    if style.tone != .control {
                        RoundedRectangle(cornerRadius: style.radius, style: .continuous)
                            .fill(.regularMaterial)
                    }

                    // 2) Base tint
                    RoundedRectangle(cornerRadius: style.radius, style: .continuous)
                        .fill(style.baseFill)

                    // 3) Accent tint
                    RoundedRectangle(cornerRadius: style.radius, style: .continuous)
                        .fill(LinearGradient(
                            colors: [
                                style.accent.opacity(0.20 * style.accentStrength),
                                .clear,
                                style.accent.opacity(0.08 * style.accentStrength)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .blendMode(.plusLighter)
                }
            )
            .overlay(
                // Lensing strokes — top bright, bottom dim, fading around
                RoundedRectangle(cornerRadius: style.radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: style.topStroke, location: 0),
                                .init(color: style.topStroke.opacity(0.3), location: 0.45),
                                .init(color: style.bottomStroke.opacity(0.55), location: 0.55),
                                .init(color: style.bottomStroke, location: 1)
                            ],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            )
            .overlay(
                // Inner highlight ring — refraction simulation
                RoundedRectangle(cornerRadius: max(2, style.radius - 1), style: .continuous)
                    .stroke(style.innerHighlight, lineWidth: 0.5)
                    .padding(0.75)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: style.radius, style: .continuous))
            // 4) Multi-layer shadows — ambient close + accent drop far
            .shadow(color: style.ambientShadow, radius: 6, x: 0, y: 2)
            .shadow(color: style.dropShadow, radius: 28, x: 0, y: 14)
    }
}

// MARK: - Liquid Glass HUD (floating)
//
// Used for toolbars / detached panels: same body but with a stronger
// shadow and prominent tone preset.

extension View {
    func liquidGlassHUD(radius: CGFloat = Radius.panel, accent: Color = .accentColor) -> some View {
        self.liquidGlass(LiquidGlassStyle(radius: radius, accent: accent, accentStrength: 0.18, tone: .prominent))
    }

    func liquidGlassControl(radius: CGFloat = Radius.control, accent: Color = .accentColor, accentStrength: Double = 0.0) -> some View {
        self.liquidGlass(LiquidGlassStyle(radius: radius, accent: accent, accentStrength: accentStrength, tone: .control))
    }
}

// MARK: - Refractive Border (standalone)
//
// Apply directly to existing shapes that already have their own
// background (e.g. images) to add a glass-like edge highlight without
// rebuilding the body.

extension View {
    func refractiveBorder(radius: CGFloat, accent: Color = .accentColor, isActive: Bool = false) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: isActive ? accent.opacity(0.7) : Surface.glassTopStroke, location: 0),
                            .init(color: Surface.glassInnerHighlight, location: 0.5),
                            .init(color: isActive ? accent.opacity(0.4) : Surface.glassBottomStroke, location: 1)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: isActive ? 1 : 0.6
                )
        )
    }
}
