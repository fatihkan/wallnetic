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
    @State private var lastCursorWrite: TimeInterval = 0

    /// P0-3: cap cursor → state writes at ~30 Hz so AmbientStage body
    /// doesn't redraw 4 stacked radials + grain at 120 Hz when the user
    /// just twitches the mouse.
    ///
    /// ORTA-3: even with throttle each accepted write triggers a SwiftUI
    /// invalidation. The static ambient layers (drift + vignette) are
    /// hoisted out of this view's body so only the cursorSpotlight
    /// sub-view actually redraws at 30 Hz.
    private static let cursorThrottle: TimeInterval = 1.0 / 30.0

    func body(content: Content) -> some View {
        ZStack {
            content
            // Drift + vignette layers — these depend only on driftPhase
            // and ignore the cursor; isolated so cursor invalidation
            // doesn't redraw the whole stack.
            staticAmbient
                .allowsHitTesting(false)
                .blendMode(.plusLighter)
            // Cursor spotlight — separated view; its own redraws don't
            // dirty the static ambient layers above.
            if cursorInside {
                cursorSpotlight
                    .allowsHitTesting(false)
                    .blendMode(.plusLighter)
                    .transition(.opacity)
            }
            // Anti-banding noise — applied once over the whole stage so
            // every radial gradient layer dithers cleanly. Rasterized
            // via drawingGroup() inside GrainOverlay.
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
                            let now = CACurrentMediaTime()
                            guard now - lastCursorWrite >= Self.cursorThrottle else { return }
                            lastCursorWrite = now
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

    /// Subtle base wash so the whole window is never pure black/white, even
    /// before content fades in. Theme-aware via `Surface.stageFloor`.
    private var stageFloor: some View {
        ZStack {
            Surface.stageFloor
            // Inverted radial — pulls the accent glow toward the center
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

    /// Drift + vignette only — depends on driftPhase, not cursor.
    private var staticAmbient: some View {
        GeometryReader { geo in
            let driftX = 0.30 + driftPhase * 0.40
            let driftY = 0.18 + sin(driftPhase * .pi) * 0.10

            ZStack {
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

                RadialGradient(
                    colors: [accent.secondary.opacity(0.10 * accent.glow), .clear],
                    center: UnitPoint(x: 1.0 - driftX, y: 0.85 - driftY * 0.6),
                    startRadius: 20,
                    endRadius: 420
                )

                RadialGradient(
                    colors: [.clear, Surface.vignetteEdge],
                    center: .center,
                    startRadius: min(geo.size.width, geo.size.height) * 0.35,
                    endRadius: max(geo.size.width, geo.size.height) * 0.75
                )
                .blendMode(.multiply)
            }
        }
    }

    /// Cursor spotlight — separate so its high-frequency updates don't
    /// redraw the static ambient stack.
    private var cursorSpotlight: some View {
        RadialGradient(
            colors: [accent.primary.opacity(0.13 * accent.glow), .clear],
            center: UnitPoint(x: cursor.x, y: cursor.y),
            startRadius: 4,
            endRadius: 180
        )
        .animation(.easeOut(duration: 0.18), value: cursor)
    }
}

extension View {
    /// Wraps the view in the global ambient stage. Apply once near the
    /// app's root.
    func ambientStage() -> some View {
        modifier(AmbientStage())
    }
}
