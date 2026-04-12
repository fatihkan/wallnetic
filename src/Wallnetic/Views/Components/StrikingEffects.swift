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

// MARK: - Glow Card Modifier

struct GlowCardModifier: ViewModifier {
    let isHovering: Bool
    let cornerRadius: CGFloat
    var glowColor: Color = .accentColor

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        isHovering
                            ? glowColor.opacity(0.4)
                            : Color.white.opacity(0.06),
                        lineWidth: isHovering ? 1 : 0.5
                    )
            )
            .shadow(
                color: isHovering ? glowColor.opacity(0.2) : .clear,
                radius: 8
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

// MARK: - Shimmer Effect

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    let p = phase
                    let loc0 = max(0, min(p - 0.15, 1.0))
                    let loc1 = max(loc0, min(p, 1.0))
                    let loc2 = max(loc1, min(p + 0.15, 1.0))
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: loc0),
                            .init(color: .white.opacity(0.06), location: loc1),
                            .init(color: .clear, location: loc2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .allowsHitTesting(false)
            )
            .onAppear {
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                    phase = 1.3
                }
            }
    }
}

// MARK: - Staggered Appearance

struct StaggeredAppearance: ViewModifier {
    let index: Int
    let total: Int
    @State private var isVisible = false

    private var delay: Double {
        min(Double(index) * 0.04, 0.8)
    }

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 16)
            .scaleEffect(isVisible ? 1 : 0.95)
            .onAppear {
                withAnimation(.spring(response: Anim.medium, dampingFraction: 0.8).delay(delay)) {
                    isVisible = true
                }
            }
    }
}

// MARK: - Neon Glow Text/Icon

struct NeonGlow: ViewModifier {
    let color: Color
    let isActive: Bool
    var radius: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .shadow(color: isActive ? color.opacity(0.35) : .clear, radius: radius * 0.5)
            .shadow(color: isActive ? color.opacity(0.15) : .clear, radius: radius)
    }
}

// MARK: - Parallax Hover Effect

struct ParallaxHover: ViewModifier {
    let isHovering: Bool

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(isHovering ? 1.5 : 0),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.8
            )
    }
}

// MARK: - Mesh Gradient Background (macOS 15+)

struct AnimatedGradientBackground: View {
    @State private var animateGradient = false

    var body: some View {
        LinearGradient(
            colors: [
                Color.black,
                Color(red: 0.05, green: 0.02, blue: 0.12),
                Color(red: 0.02, green: 0.05, blue: 0.1),
                Color.black
            ],
            startPoint: animateGradient ? .topLeading : .bottomLeading,
            endPoint: animateGradient ? .bottomTrailing : .topTrailing
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
}

// MARK: - Card Flip

struct CardFlip<Back: View>: ViewModifier {
    @Binding var isFlipped: Bool
    let back: Back

    init(isFlipped: Binding<Bool>, @ViewBuilder back: () -> Back) {
        self._isFlipped = isFlipped
        self.back = back()
    }

    func body(content: Content) -> some View {
        ZStack {
            content
                .opacity(isFlipped ? 0 : 1)
                .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))

            back
                .opacity(isFlipped ? 1 : 0)
                .rotation3DEffect(.degrees(isFlipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
        }
        .animation(Anim.gentle, value: isFlipped)
    }
}

extension View {
    func cardFlip<Back: View>(isFlipped: Binding<Bool>, @ViewBuilder back: () -> Back) -> some View {
        modifier(CardFlip(isFlipped: isFlipped, back: back))
    }
}

// MARK: - Press Effect (scale down on click)

struct PressEffect: ViewModifier {
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(Anim.press, value: isPressed)
            .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                isPressed = pressing
            }, perform: {})
    }
}

// MARK: - View Extensions

extension View {
    func glowCard(isHovering: Bool, cornerRadius: CGFloat = 10, glowColor: Color = .accentColor) -> some View {
        modifier(GlowCardModifier(isHovering: isHovering, cornerRadius: cornerRadius, glowColor: glowColor))
    }

    func glassBackground(cornerRadius: CGFloat = 12, opacity: Double = 0.06) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius, opacity: opacity))
    }

    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }

    func staggered(index: Int, total: Int = 20) -> some View {
        modifier(StaggeredAppearance(index: index, total: total))
    }

    func neonGlow(_ color: Color, isActive: Bool, radius: CGFloat = 8) -> some View {
        modifier(NeonGlow(color: color, isActive: isActive, radius: radius))
    }

    func parallaxHover(isHovering: Bool) -> some View {
        modifier(ParallaxHover(isHovering: isHovering))
    }

    func pressEffect() -> some View {
        modifier(PressEffect())
    }
}

// MARK: - Safe Array Subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
