import SwiftUI

// MARK: - Animation Timing

enum Anim {
    // Durations
    static let micro: Double = 0.1
    static let fast: Double = 0.15
    static let normal: Double = 0.2
    static let enter: Double = 0.25
    static let medium: Double = 0.3
    static let expand: Double = 0.35
    static let slow: Double = 0.4
    static let hero: Double = 0.8

    // Spring presets
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.7)
    static let gentle = Animation.spring(response: 0.5, dampingFraction: 0.8)
    static let bouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)
    static let stiff = Animation.spring(response: 0.2, dampingFraction: 0.9)

    // Interactive
    static let hover = Animation.easeOut(duration: normal)
    static let press = Animation.easeIn(duration: micro)
    static let transition = Animation.easeInOut(duration: medium)
}

// MARK: - Card Highlight Modifier

/// A plain hover outline for cards. It replaced the accent glow (#343 B1):
/// a neutral stroke reads in light and dark appearance and sits quietly next
/// to macOS 26 system chrome.
struct CardHighlightModifier: ViewModifier {
    let isHovering: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        Color.primary.opacity(isHovering ? 0.28 : 0.08),
                        lineWidth: isHovering ? 1 : 0.5
                    )
            )
    }
}

// MARK: - Glass Background Modifier

struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 12
    var opacity: Double = 0.06

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.white.opacity(opacity))
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial.opacity(0.3))
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                }
            )
    }
}

// MARK: - Staggered Appearance

struct StaggeredAppearance: ViewModifier {
    let index: Int
    let total: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    private var delay: Double {
        min(Double(index) * 0.04, 0.8)
    }

    func body(content: Content) -> some View {
        // With Reduce Motion on, items appear in place without sliding or scaling.
        let shown = isVisible || reduceMotion
        return content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 16)
            .scaleEffect(shown ? 1 : 0.95)
            .onAppear {
                guard !reduceMotion else { isVisible = true; return }
                withAnimation(.spring(response: Anim.medium, dampingFraction: 0.8).delay(delay)) {
                    isVisible = true
                }
            }
    }
}

// MARK: - View Extensions

extension View {
    func cardHighlight(isHovering: Bool, cornerRadius: CGFloat = 10) -> some View {
        modifier(CardHighlightModifier(isHovering: isHovering, cornerRadius: cornerRadius))
    }

    func glassBackground(cornerRadius: CGFloat = 12, opacity: Double = 0.06) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius, opacity: opacity))
    }

    func staggered(index: Int, total: Int = 20) -> some View {
        modifier(StaggeredAppearance(index: index, total: total))
    }
}

// MARK: - Safe Array Subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
