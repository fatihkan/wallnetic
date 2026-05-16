import SwiftUI
import AppKit
import Combine

/// 2026 Apple-style content-derived accent. Reads the active wallpaper's
/// dominant color and derives a small palette (primary, secondary, on-color,
/// glow strength) that the chrome consumes everywhere it would otherwise
/// hard-code `.accentColor`.
///
/// Differs from `ThemeManager.accentColor` in two ways:
///   1. Always-on (it's part of the design language now, not a user toggle).
///   2. Publishes a full **AccentTheme** struct, not just one color — so a
///      sheet header can use `.primary` for its icon orb while the lensing
///      stroke samples `.secondary`.
///
/// Falls back to a Wallnetic signature palette when no wallpaper is active
/// or its dominant color has not been extracted yet.
@MainActor
final class DynamicAccent: ObservableObject {
    static let shared = DynamicAccent()

    @Published private(set) var theme: AccentTheme = .signature

    private var observer: Any?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .wallpaperDidChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let wp = note.object as? Wallpaper else { return }
            Task { @MainActor in
                self?.applyFrom(wallpaper: wp)
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func applyFrom(wallpaper: Wallpaper?) {
        guard let wp = wallpaper else {
            withAnimation(.easeInOut(duration: 0.8)) { theme = .signature }
            return
        }

        if let hex = wp.dominantColorHex, let ns = NSColor(hex: hex) {
            withAnimation(.easeInOut(duration: 0.8)) {
                theme = AccentTheme.derive(from: ns)
            }
            return
        }

        // Extract on demand, then apply once available.
        Task { [weak self] in
            if let hex = await wp.extractDominantColor(), let ns = NSColor(hex: hex) {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.8)) {
                        self?.theme = AccentTheme.derive(from: ns)
                    }
                }
            }
        }
    }
}

// MARK: - Accent Theme

struct AccentTheme: Equatable {
    let primary: Color
    let secondary: Color
    /// Color that sits *on top* of the primary fill (text/icon over an
    /// accent-colored button) — high-contrast counterpart.
    let on: Color
    /// 0–1 scalar for shadow/glow intensity. Pastel/light palettes get a
    /// stronger glow because they need it to read; saturated palettes
    /// already pop.
    let glow: Double

    /// Wallnetic's fallback when no wallpaper accent is available.
    static let signature = AccentTheme(
        primary: Color(red: 0.36, green: 0.78, blue: 1.00),       // signature cyan-blue
        secondary: Color(red: 0.68, green: 0.45, blue: 1.00),     // electric violet
        on: .black,
        glow: 0.65
    )

    static func derive(from nsColor: NSColor) -> AccentTheme {
        let rgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: nil)

        // Lift muddy/dim wallpaper colors into a vivid usable accent.
        let liftedS = max(s, 0.55)
        let liftedB = min(max(b, 0.55), 0.92)

        let primaryNS = NSColor(hue: h, saturation: liftedS, brightness: liftedB, alpha: 1)
        // Secondary: 32° hue rotation toward complementary — keeps it
        // harmonic rather than clashing.
        let secondaryNS = NSColor(
            hue: (h + 32.0 / 360.0).truncatingRemainder(dividingBy: 1),
            saturation: min(1, liftedS * 0.9),
            brightness: min(1, liftedB * 1.05),
            alpha: 1
        )

        let on: Color = liftedB > 0.6 ? .black : .white
        let glow = 0.45 + Double(1 - liftedS) * 0.4  // pastel → more glow

        return AccentTheme(
            primary: Color(nsColor: primaryNS),
            secondary: Color(nsColor: secondaryNS),
            on: on,
            glow: min(1, glow)
        )
    }
}

// MARK: - Environment plumbing
//
// Most chrome can read the accent off `@EnvironmentObject DynamicAccent`,
// but for sub-views that don't have it injected we also expose an
// environment key so call sites stay short.

private struct AccentThemeKey: EnvironmentKey {
    static let defaultValue: AccentTheme = .signature
}

extension EnvironmentValues {
    var accentTheme: AccentTheme {
        get { self[AccentThemeKey.self] }
        set { self[AccentThemeKey.self] = newValue }
    }
}
