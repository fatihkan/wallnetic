import SwiftUI
import AppKit

// MARK: - Concentric Radius Scale
//
// Apple's 2026 system: nested corners follow `inner = outer - inset` so
// the curvature stays parallel. Pick one outer value, then derive the rest
// from the padding you add. These constants codify the chain we use.

enum Radius {
    /// Window edge — top of the chain.
    static let window: CGFloat = 18
    /// Floating panels (sheets, floating toolbars, HUDs).
    static let panel: CGFloat = 16
    /// Cards (hero, carousel, grid).
    static let card: CGFloat = 12
    /// Controls (buttons, fields, chips).
    static let control: CGFloat = 10
    /// Tags / capsules.
    static let tag: CGFloat = 8
    /// Inner accents (selection rings, dots).
    static let accent: CGFloat = 6

    /// Compute inner radius from a containing outer radius and the inset
    /// between them. Clamped to a minimum of `Radius.accent` so the inner
    /// never degenerates to a sharp corner.
    static func nested(in outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(accent, outer - inset)
    }
}

// MARK: - Spacing Scale
//
// 4-pt grid. Use the named values; never sprinkle raw numbers.

enum Space {
    static let micro: CGFloat = 2
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
    static let xxl: CGFloat = 40
}

// MARK: - Typography Scale
//
// 2026 SF Pro with explicit tracking. Use these instead of inline
// `.font(.system(...))` so the type voice stays consistent across the app.

enum Typo {
    // Display — hero titles, single-line, dramatic
    static let display: Font = .system(size: 34, weight: .bold, design: .rounded)
    static let displayTracking: CGFloat = -0.6

    // Title 1 — section heroes, sheet headers
    static let title1: Font = .system(size: 22, weight: .bold, design: .rounded)
    static let title1Tracking: CGFloat = -0.4

    // Title 2 — group titles
    static let title2: Font = .system(size: 17, weight: .semibold, design: .rounded)
    static let title2Tracking: CGFloat = -0.2

    // Body
    static let body: Font = .system(size: 13, weight: .regular)
    static let bodyTracking: CGFloat = 0

    // Caption
    static let caption: Font = .system(size: 11, weight: .medium)
    static let captionTracking: CGFloat = 0.1

    // Kicker — uppercase monospaced labels (e.g. "01 · IMPORT")
    static let kicker: Font = .system(size: 9, weight: .heavy, design: .monospaced)
    static let kickerTracking: CGFloat = 2.5

    // Data — numbers, paths, dimensions
    static let data: Font = .system(size: 11, weight: .medium, design: .monospaced)
    static let dataTracking: CGFloat = 0.2

    // Button label
    static let button: Font = .system(size: 13, weight: .semibold, design: .rounded)
    static let buttonTracking: CGFloat = 0.3
}

// MARK: - Reusable Text Styles

extension Text {
    func styledKicker(color: Color = .white.opacity(0.4)) -> some View {
        self
            .font(Typo.kicker)
            .tracking(Typo.kickerTracking)
            .foregroundColor(color)
            .textCase(.uppercase)
    }

    func styledData(color: Color = .white.opacity(0.5)) -> some View {
        self
            .font(Typo.data)
            .tracking(Typo.dataTracking)
            .foregroundColor(color)
    }
}

// MARK: - Adaptive Surface Palette
//
// One source of truth for every "this should be dark in dark mode, light
// in light mode" color. Built on top of NSColor's dynamic provider so the
// color tracks NSApp.appearance in real time — no @Environment plumbing.

extension Color {
    /// Returns dark on .darkAqua, light on .aqua. Tracks NSApp.appearance.
    static func adaptive(dark: Color, light: Color) -> Color {
        Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? NSColor(dark) : NSColor(light)
        })
    }
}

/// Theme-aware surface tokens. Numbers chosen to match the existing dark
/// stage exactly; light variants picked for contrast against `.primary`
/// text and to keep accent gradients legible.
enum Surface {
    /// Deepest backdrop behind everything (ambient stage floor).
    static var stageFloor: Color { .adaptive(
        dark:  Color(red: 0.02, green: 0.025, blue: 0.05),
        light: Color(red: 0.96, green: 0.965, blue: 0.98)
    )}

    /// Settings + onboarding window-fill background.
    static var windowFill: Color { .adaptive(
        dark:  Color(red: 0.04, green: 0.05, blue: 0.09),
        light: Color(red: 0.97, green: 0.975, blue: 0.985)
    )}

    /// HomeView vignette / footer fade target.
    static var deepFade: Color { .adaptive(
        dark:  Color(red: 0.02, green: 0.02, blue: 0.06),
        light: Color(red: 0.94, green: 0.945, blue: 0.96)
    )}

    /// Vignette darkening (or in light mode, mild edge softening).
    static var vignetteEdge: Color { .adaptive(
        dark:  .black.opacity(0.35),
        light: .black.opacity(0.06)
    )}

    /// Liquid Glass base fill — standard tone.
    static var glassStandard: Color { .adaptive(
        dark:  .black.opacity(0.18),
        light: .white.opacity(0.55)
    )}

    /// Liquid Glass base fill — prominent tone (denser floating chrome).
    static var glassProminent: Color { .adaptive(
        dark:  .black.opacity(0.32),
        light: .white.opacity(0.70)
    )}

    /// Liquid Glass base fill — control tone (no material blur).
    static var glassControl: Color { .adaptive(
        dark:  .white.opacity(0.05),
        light: .black.opacity(0.04)
    )}

    /// Top lensing stroke — bright on glass.
    static var glassTopStroke: Color { .adaptive(
        dark:  .white.opacity(0.16),
        light: .white.opacity(0.85)
    )}

    /// Bottom lensing stroke — dim on glass.
    static var glassBottomStroke: Color { .adaptive(
        dark:  .black.opacity(0.32),
        light: .black.opacity(0.14)
    )}

    /// Inner refraction highlight.
    static var glassInnerHighlight: Color { .adaptive(
        dark:  .white.opacity(0.06),
        light: .white.opacity(0.55)
    )}

    /// Generic divider hairline color.
    static var hairline: Color { .adaptive(
        dark:  .white.opacity(0.06),
        light: .black.opacity(0.08)
    )}
}
