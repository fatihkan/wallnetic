import SwiftUI

/// 2026 Apple-style ambient lighting for the whole window. Three layers:
///
///   1. **Drift** — a slow radial wash that travels along an ellipse over
///      ~22 s. Gives the entire UI the feel of standing in a room with one
///      moving light source.
///   2. **Vignette** — soft edge darkening so the eye always returns to
///      center content.
///   3. **Cursor spotlight** — a faint accent-colored soft light that
///      follows the pointer across the window. Like the highlight Vision
///      Pro applies to whatever you're looking at — except mouse-driven
///      because we are on macOS.
///
/// Costs: one continuous low-cadence animation + one onContinuousHover
/// observer at the root. Both are cheap.
struct AmbientStage: ViewModifier {
    @Environment(\.accentTheme) private var accent
    @State private var driftPhase: Double = 0
    @State private var cursor: CGPoint = .init(x: 0.5, y: 0.5)
    @State private var cursorInside: Bool = false

    func body(content: Content) -> some View {
        ZStack {
            content
            ambientOverlay
                .allowsHitTesting(false)
                .blendMode(.plusLighter)
            // Anti-banding noise — applied once over the whole stage so
            // every radial gradient layer dithers cleanly.
            GrainOverlay(intensity: 0.04)
                .ignoresSafeArea()
        }
        .background(stageFloor.ignoresSafeArea())
        .onAppear {
            withAnimation(.linear(duration: 22).repeatForever(autoreverses: true)) {
                driftPhase = 1
            }
        }
        .overlay(
            // Cursor tracker
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p):
                            cursor = CGPoint(
                                x: min(max(p.x / geo.size.width, 0), 1),
                                y: min(max(p.y / geo.size.height, 0), 1)
                            )
                            cursorInside = true
                        case .ended:
                            cursorInside = false
                        }
                    }
                    .allowsHitTesting(false)
            }
        )
    }

    // MARK: - Floor (behind content)

    /// Subtle base wash so the whole window is never pure black, even
    /// before content fades in.
    private var stageFloor: some View {
        ZStack {
            Color(red: 0.02, green: 0.025, blue: 0.05)
            // Inverted radial — darker at corners
            RadialGradient(
                colors: [accent.primary.opacity(0.05 * accent.glow), .clear],
                center: .init(x: 0.5, y: 0.4),
                startRadius: 100,
                endRadius: 700
            )
            .opacity(0.7)
        }
    }

    // MARK: - Overlay (in front of content)

    private var ambientOverlay: some View {
        GeometryReader { geo in
            let driftX = 0.30 + driftPhase * 0.40
            let driftY = 0.18 + sin(driftPhase * .pi) * 0.10

            ZStack {
                // 1) Drifting accent wash
                RadialGradient(
                    colors: [
                        accent.primary.opacity(0.16 * accent.glow),
                        accent.primary.opacity(0.06 * accent.glow),
                        .clear
                    ],
                    center: UnitPoint(x: driftX, y: driftY),
                    startRadius: 20,
                    endRadius: 500
                )

                // 2) Secondary drift (counter direction)
                RadialGradient(
                    colors: [accent.secondary.opacity(0.10 * accent.glow), .clear],
                    center: UnitPoint(x: 1.0 - driftX, y: 0.85 - driftY * 0.6),
                    startRadius: 20,
                    endRadius: 420
                )

                // 3) Vignette
                RadialGradient(
                    colors: [.clear, .black.opacity(0.35)],
                    center: .center,
                    startRadius: min(geo.size.width, geo.size.height) * 0.35,
                    endRadius: max(geo.size.width, geo.size.height) * 0.75
                )
                .blendMode(.multiply)

                // 4) Cursor spotlight
                if cursorInside {
                    RadialGradient(
                        colors: [accent.primary.opacity(0.13 * accent.glow), .clear],
                        center: UnitPoint(x: cursor.x, y: cursor.y),
                        startRadius: 4,
                        endRadius: 180
                    )
                    .animation(.easeOut(duration: 0.18), value: cursor)
                }
            }
        }
    }
}

extension View {
    /// Wraps the view in the global ambient stage. Apply once near the
    /// app's root.
    func ambientStage() -> some View {
        modifier(AmbientStage())
    }
}
