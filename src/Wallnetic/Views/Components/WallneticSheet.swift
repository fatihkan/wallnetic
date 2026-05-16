import SwiftUI

/// Cinematic-dark sheet chrome used by every modal across Wallnetic.
/// Replaces SwiftUI's default sheet look (white background, system chrome)
/// with the app's signature: deep navy gradient + ultraThinMaterial veil +
/// hairline accent border + soft neon corner glow.
///
/// Usage:
///
///     .sheet(isPresented: $showing) {
///         WallneticSheet(title: "Rename Collection", icon: "folder.fill") {
///             // content
///         } footer: {
///             WallneticButton.cancel { dismiss() }
///             WallneticButton.primary("Save", isEnabled: canSave) { commit() }
///         }
///     }
struct WallneticSheet<Content: View, Footer: View>: View {
    let title: String
    var icon: String? = nil
    var accent: Color = .accentColor
    var width: CGFloat = 360
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .overlay(LinearGradient(
                    colors: [.clear, accent.opacity(0.35), .clear],
                    startPoint: .leading, endPoint: .trailing
                ))
                .frame(height: 0.5)

            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            HStack(spacing: 10) {
                footer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: width)
        .background(WallneticSheetBackground(accent: accent))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(LinearGradient(
                    colors: [accent.opacity(0.35), .white.opacity(0.06), accent.opacity(0.15)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ), lineWidth: 0.5)
        )
        .shadow(color: accent.opacity(0.25), radius: 28, x: 0, y: 12)
        .shadow(color: .black.opacity(0.55), radius: 14, x: 0, y: 4)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let icon {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.18))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                        .shadow(color: accent.opacity(0.7), radius: 4)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .tracking(0.2)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

// Convenience: sheets without a footer.
extension WallneticSheet where Footer == EmptyView {
    init(
        title: String,
        icon: String? = nil,
        accent: Color = .accentColor,
        width: CGFloat = 360,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.accent = accent
        self.width = width
        self.content = content
        self.footer = { EmptyView() }
    }
}

// MARK: - Background

private struct WallneticSheetBackground: View {
    let accent: Color

    var body: some View {
        ZStack {
            // Deep base
            Color(red: 0.04, green: 0.05, blue: 0.09)

            // Subtle radial top-left tint
            RadialGradient(
                colors: [accent.opacity(0.16), .clear],
                center: .topLeading,
                startRadius: 5,
                endRadius: 240
            )

            // Bottom-right vignette
            RadialGradient(
                colors: [Color(red: 0.10, green: 0.06, blue: 0.16).opacity(0.55), .clear],
                center: .bottomTrailing,
                startRadius: 5,
                endRadius: 260
            )

            // Glass veil
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.20)

            // Grain (CoreImage noise via blendmode)
            WallneticGrain()
                .opacity(0.05)
                .blendMode(.overlay)
                .allowsHitTesting(false)
        }
    }
}

/// Static stochastic grain — tiles a tiny pseudo-random pattern via
/// Canvas. Cheap to render once per sheet appearance.
private struct WallneticGrain: View {
    var body: some View {
        Canvas { ctx, size in
            // Coarse blue-noise approximation: 600 dots, deterministic seed.
            var rng = SeedableRNG(seed: 1337)
            for _ in 0..<600 {
                let x = Double(rng.nextUInt() % UInt32(size.width))
                let y = Double(rng.nextUInt() % UInt32(size.height))
                let a = 0.04 + Double(rng.nextUInt() % 60) / 1000
                let rect = CGRect(x: x, y: y, width: 1, height: 1)
                ctx.fill(Path(rect), with: .color(.white.opacity(a)))
            }
        }
    }

    struct SeedableRNG {
        var state: UInt32
        init(seed: UInt32) { state = seed | 1 }
        mutating func nextUInt() -> UInt32 {
            state = state &* 1664525 &+ 1013904223
            return state
        }
    }
}
