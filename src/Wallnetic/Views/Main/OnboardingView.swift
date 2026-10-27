import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    var onComplete: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        OnboardingTourContent(isPresented: $isPresented, onComplete: onComplete,
                              reduceMotion: reduceMotion, scenePhase: scenePhase)
    }
}

/// Keep the tour's identity stable when environment preferences change so an
/// ongoing sample/import is not cancelled. Explicit inputs also allow isolated
/// previews without changing system accessibility preferences.
struct OnboardingTourContent: View {
    @Binding var isPresented: Bool
    var onComplete: () -> Void = {}
    let reduceMotion: Bool
    let scenePhase: ScenePhase
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var currentStep = 0

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
            description: "Drop video files, download from the built-in browser, or try a wallpaper pack — Wallnetic accepts it all.",
            accent: Color(red: 0.30, green: 0.85, blue: 0.92),
            secondary: Color(red: 0.28, green: 0.55, blue: 1.00)
        ),
        Step(
            icon: "rectangle.stack.fill.badge.person.crop",
            title: "Curate Effortlessly",
            kicker: "02 · ORGANIZE",
            description: "Favorites, color filters and search keep your library in order.",
            accent: Color(red: 1.00, green: 0.45, blue: 0.72),
            secondary: Color(red: 0.95, green: 0.65, blue: 0.30)
        ),
        Step(
            icon: "display.2",
            title: "Every Display, Its Own Mood",
            kicker: "03 · MULTI-MONITOR",
            description: "Choose a wallpaper for each display. Space recovery saves choices to apply manually to all displays and Spaces; automatic per-Space switching is unavailable.",
            accent: Color(red: 0.40, green: 0.95, blue: 0.55),
            secondary: Color(red: 0.20, green: 0.85, blue: 0.85)
        ),
    ]

    private var step: Step { steps[currentStep] }
    private var animatesArtwork: Bool { !reduceMotion && scenePhase == .active }

    private func artworkPhase(at date: Date) -> Double {
        guard animatesArtwork else { return 0 }
        let seconds = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 32)
        return (1 - cos(seconds * .pi / 16)) / 2
    }

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                orb
                    .frame(height: currentStep == 0 ? 100 : 220)
                    .scaleEffect(currentStep == 0 ? 0.48 : 1)

                stepCopy
                    .padding(.top, currentStep == 0 ? 8 : 32)

                if currentStep == 0 {
                    OnboardingQuickStartView()
                        .padding(.top, 14)
                }

                Spacer(minLength: 0)

                controls
                    .padding(.horizontal, 40)
                    .padding(.bottom, currentStep == 0 ? 20 : 36)
            }
        }
        .frame(width: 640, height: 520)
        .fixedSize()
        .clipped()
        .modifier(OnboardingSheetSizing())
        .preferredColorScheme(themeManager.appearanceMode.swiftUIColorScheme)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animatesArtwork)) { context in
            backdrop(phase: artworkPhase(at: context.date))
        }
        .accessibilityHidden(true)
    }

    private func backdrop(phase: Double) -> some View {
        ZStack {
            Surface.stageFloor

            // Drifting accent radial
            RadialGradient(
                colors: [step.accent.opacity(0.32), .clear],
                center: UnitPoint(x: 0.2 + phase * 0.15, y: 0.18),
                startRadius: 8,
                endRadius: 420
            )

            // Secondary radial bottom-right
            RadialGradient(
                colors: [step.secondary.opacity(0.22), .clear],
                center: UnitPoint(x: 0.85, y: 0.85 - phase * 0.1),
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
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: currentStep)
    }

    // MARK: - Orb (animated icon stage)

    private var orb: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animatesArtwork)) { context in
            orb(phase: artworkPhase(at: context.date))
        }
        .accessibilityHidden(true)
    }

    private func orb(phase: Double) -> some View {
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
                    .scaleEffect(1 + (phase * 0.04) * Double(i + 1))
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
                .scaleEffect(1 + phase * 0.03)

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
                .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
                .id("icon-\(currentStep)")
        }
        .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.78), value: currentStep)
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
                .accessibilityAddTraits(.isHeader)

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
        .transition(reduceMotion ? .identity : .asymmetric(
            insertion: .offset(y: 12).combined(with: .opacity),
            removal: .offset(y: -8).combined(with: .opacity)
        ))
        .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.82), value: currentStep)
    }

    private func finish() {
        onComplete()
        withAnimation(reduceMotion ? nil : .default) { isPresented = false }
    }

    // MARK: - Controls (progress + buttons)

    private var controls: some View {
        VStack(spacing: 24) {
            // Capsule progress
            HStack(spacing: 6) {
                Text("Step \(currentStep + 1) of \(steps.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
                    .accessibilityLabel("Welcome tour, step \(currentStep + 1) of \(steps.count)")
                ForEach(0..<steps.count, id: \.self) { i in
                    Capsule()
                        .fill(i == currentStep ? AnyShapeStyle(LinearGradient(
                                colors: [step.accent, step.secondary],
                                startPoint: .leading, endPoint: .trailing
                            )) : AnyShapeStyle(Color.primary.opacity(0.18)))
                        .frame(width: i == currentStep ? 28 : 12, height: 4)
                        .shadow(color: i == currentStep ? step.accent.opacity(0.6) : .clear, radius: 4)
                        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.75), value: currentStep)
                        .accessibilityHidden(true)
                }
            }

            HStack {
                if currentStep > 0 {
                    WallneticButton.cancel("Back") {
                        withAnimation(reduceMotion ? nil : .default) { currentStep -= 1 }
                    }
                } else {
                    WallneticButton.cancel("Skip") {
                        finish()
                    }
                }

                Spacer()

                if currentStep < steps.count - 1 {
                    WallneticButton.primary("Next", icon: "arrow.right", accent: step.accent) {
                        withAnimation(reduceMotion ? nil : .default) { currentStep += 1 }
                    }
                } else {
                    WallneticButton.primary("Enter Wallnetic", icon: "sparkles", accent: step.accent) {
                        finish()
                    }
                }
            }
        }
    }
}

/// New SDKs support explicit fitted presentation sizing. Keep fixedSize as
/// the fallback for older systems and the project's Xcode 15.2 toolchain.
private struct OnboardingSheetSizing: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.0)
        if #available(macOS 15.0, *) {
            content.presentationSizing(.fitted)
        } else {
            content
        }
        #else
        content
        #endif
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
