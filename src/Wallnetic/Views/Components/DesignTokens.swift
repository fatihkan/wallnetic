import SwiftUI

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
