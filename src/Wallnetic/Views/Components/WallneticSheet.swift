import SwiftUI

/// 2026 Liquid Glass sheet chrome. Uses the `LiquidGlass` primitive for
/// the actual surface (refractive edges, multi-layer shadow, accent
/// tint), and applies concentric inner radii to anything nested inside.
///
/// Usage:
///
///     .sheet(isPresented: $showing) {
///         WallneticSheet(title: "Rename", icon: "pencil") {
///             // content
///         } footer: {
///             WallneticButton.cancel { dismiss() }
///             Spacer()
///             WallneticButton.primary("Save", isEnabled: canSave) { commit() }
///         }
///     }
struct WallneticSheet<Content: View, Footer: View>: View {
    let title: String
    var icon: String? = nil
    var accent: Color = .accentColor
    var width: CGFloat = 380
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            header
            divider

            VStack(alignment: .leading, spacing: Space.md) {
                content()
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)

            HStack(spacing: Space.xs) {
                footer()
            }
            .padding(.horizontal, Space.lg)
            .padding(.bottom, Space.md)
        }
        .frame(width: width)
        .liquidGlass(LiquidGlassStyle(
            radius: Radius.panel,
            accent: accent,
            accentStrength: 0.14,
            tone: .prominent
        ))
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Space.sm) {
            if let icon {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.20))
                    Circle()
                        .strokeBorder(accent.opacity(0.4), lineWidth: 0.5)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                        .shadow(color: accent.opacity(0.75), radius: 4)
                }
                .frame(width: 30, height: 30)
            }

            Text(title)
                .font(Typo.title2)
                .tracking(Typo.title2Tracking)
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
    }

    // MARK: - Divider (gradient hairline)

    private var divider: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [.clear, accent.opacity(0.35), .clear],
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(height: 0.5)
    }
}

// Convenience: sheets without a footer.
extension WallneticSheet where Footer == EmptyView {
    init(
        title: String,
        icon: String? = nil,
        accent: Color = .accentColor,
        width: CGFloat = 380,
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
