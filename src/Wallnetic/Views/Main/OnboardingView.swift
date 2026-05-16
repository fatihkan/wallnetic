import SwiftUI

/// Cinematic 4-step onboarding. Full-bleed dark stage, animated gradient
/// orb, staggered typography reveal, custom progress capsule.
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var currentStep = 0
    @State private var orbPhase: Double = 0

    private struct Step {
        let icon: String
        let title: String
        let kicker: String
        let description: String
        let accent: Color
        let secondary: Color
    }

    private let steps: [Step] = [
        Step(
            icon: "sparkles.tv.fill",
            title: "Wallnetic",
            kicker: "LIVE WALLPAPERS",
            description: "Cinematic, GPU-accelerated motion behind every window. Built for macOS.",
            accent: Color(red: 0.42, green: 0.71, blue: 1.00),
            secondary: Color(red: 0.65, green: 0.45, blue: 1.00)
        ),
        Step(
            icon: "tray.and.arrow.down.fill",
            title: "Bring Anything In",
            kicker: "01 · IMPORT",
            description: "Drop video files, link from the browser, or generate with AI — Wallnetic accepts it all.",
            accent: Color(red: 0.30, green: 0.85, blue: 0.92),
            secondary: Color(red: 0.28, green: 0.55, blue: 1.00)
        ),
        Step(
            icon: "rectangle.stack.fill.badge.person.crop",
            title: "Curate Effortlessly",
            kicker: "02 · ORGANIZE",
            description: "Collections, favorites, color filters and now smart auto-tags via local Ollama Vision.",
            accent: Color(red: 1.00, green: 0.45, blue: 0.72),
            secondary: Color(red: 0.95, green: 0.65, blue: 0.30)
        ),
        Step(
            icon: "display.2",
            title: "Every Display, Its Own Mood",
            kicker: "03 · MULTI-MONITOR",
            description: "Assign distinct wallpapers per screen and per Space. Pause on battery, fullscreen, or schedule.",
            accent: Color(red: 0.40, green: 0.95, blue: 0.55),
            secondary: Color(red: 0.20, green: 0.85, blue: 0.85)
        ),
    ]

    private var step: Step { steps[currentStep] }

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                orb
                    .frame(height: 220)

                stepCopy
                    .padding(.top, 32)

                Spacer(minLength: 0)

                controls
                    .padding(.horizontal, 40)
                    .padding(.bottom, 36)
            }
        }
        .frame(width: 640, height: 520)
        .preferredColorScheme(themeManager.appearanceMode.swiftUIColorScheme)
        .onAppear {
            withAnimation(.linear(duration: 16).repeatForever(autoreverses: true)) {
                orbPhase = 1
            }
        }
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        ZStack {
            Surface.stageFloor

            // Drifting accent radial
            RadialGradient(
                colors: [step.accent.opacity(0.32), .clear],
                center: UnitPoint(x: 0.2 + orbPhase * 0.15, y: 0.18),
                startRadius: 8,
                endRadius: 420
            )

            // Secondary radial bottom-right
            RadialGradient(
                colors: [step.secondary.opacity(0.22), .clear],
                center: UnitPoint(x: 0.85, y: 0.85 - orbPhase * 0.1),
                startRadius: 8,
                endRadius: 380
            )

            // Diagonal noise lines
            DiagonalLines()
                .stroke(Surface.glassInnerHighlight.opacity(0.4), lineWidth: 0.5)
                .allowsHitTesting(false)

            // Vignette
            RadialGradient(
                colors: [.clear, Surface.vignetteEdge.opacity(1.3)],
                center: .center,
                startRadius: 200,
                endRadius: 550
            )
        }
        .animation(.easeInOut(duration: 0.8), value: currentStep)
    }

    // MARK: - Orb (animated icon stage)

    private var orb: some View {
        ZStack {
            // Outer rings
            ForEach(0..<3) { i in
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [step.accent.opacity(0.5), step.secondary.opacity(0.0)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
                    .frame(width: 160 + CGFloat(i) * 36, height: 160 + CGFloat(i) * 36)
                    .scaleEffect(1 + (orbPhase * 0.04) * Double(i + 1))
                    .opacity(0.6 - Double(i) * 0.18)
            }

            // Glow blob
            Circle()
                .fill(
                    RadialGradient(
                        colors: [step.accent.opacity(0.55), step.secondary.opacity(0.15), .clear],
                        center: .center,
                        startRadius: 4,
                        endRadius: 130
                    )
                )
                .frame(width: 220, height: 220)
                .blur(radius: 8)
                .scaleEffect(1 + orbPhase * 0.03)

            // Core disk
            Circle()
                .fill(
                    LinearGradient(
                        colors: [step.accent, step.secondary],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: 96, height: 96)
                .overlay(
                    Circle().stroke(.white.opacity(0.25), lineWidth: 0.5)
                )
                .shadow(color: step.accent.opacity(0.7), radius: 24, y: 8)

            // Icon
            Image(systemName: step.icon)
                .font(.system(size: 36, weight: .semibold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
                .transition(.scale.combined(with: .opacity))
                .id("icon-\(currentStep)")
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.78), value: currentStep)
    }

    // MARK: - Step copy

    private var stepCopy: some View {
        VStack(spacing: 12) {
            Text(step.kicker)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(2.5)
                .foregroundColor(step.accent.opacity(0.85))

            Text(step.title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .tracking(-0.4)
                .multilineTextAlignment(.center)

            Text(step.description)
                .font(.system(size: 13))
                .foregroundColor(.primary.opacity(0.72))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 380)
                .padding(.top, 2)
        }
        .padding(.horizontal, 40)
        .id("copy-\(currentStep)")
        .transition(.asymmetric(
            insertion: .offset(y: 12).combined(with: .opacity),
            removal: .offset(y: -8).combined(with: .opacity)
        ))
        .animation(.spring(response: 0.55, dampingFraction: 0.82), value: currentStep)
    }

    // MARK: - Controls (progress + buttons)

    private var controls: some View {
        VStack(spacing: 24) {
            // Capsule progress
            HStack(spacing: 6) {
                ForEach(0..<steps.count, id: \.self) { i in
                    Capsule()
                        .fill(i == currentStep ? AnyShapeStyle(LinearGradient(
                                colors: [step.accent, step.secondary],
                                startPoint: .leading, endPoint: .trailing
                            )) : AnyShapeStyle(Color.primary.opacity(0.18)))
                        .frame(width: i == currentStep ? 28 : 12, height: 4)
                        .shadow(color: i == currentStep ? step.accent.opacity(0.6) : .clear, radius: 4)
                        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: currentStep)
                }
            }

            HStack {
                if currentStep > 0 {
                    WallneticButton.cancel("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                } else {
                    WallneticButton.cancel("Skip") {
                        withAnimation { isPresented = false }
                    }
                }

                Spacer()

                if currentStep < steps.count - 1 {
                    WallneticButton.primary("Next", icon: "arrow.right", accent: step.accent) {
                        withAnimation { currentStep += 1 }
                    }
                } else {
                    WallneticButton.primary("Enter Wallnetic", icon: "sparkles", accent: step.accent) {
                        withAnimation { isPresented = false }
                    }
                }
            }
        }
    }
}

// MARK: - Diagonal Lines (backdrop texture)

private struct DiagonalLines: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let spacing: CGFloat = 32
        var x: CGFloat = -rect.height
        while x < rect.width {
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.height))
            x += spacing
        }
        return p
    }
}
