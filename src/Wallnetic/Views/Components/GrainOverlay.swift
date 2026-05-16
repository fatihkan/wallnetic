import SwiftUI

/// Static stochastic grain. SwiftUI's gradients render at 8-bit color
/// depth without dithering, so very dark/low-contrast gradients (the
/// kind every cinematic dark UI uses) show banding as visible concentric
/// rings. A 1-2% noise overlay destroys the banding because the eye
/// averages noise back to the smooth gradient.
///
/// Canvas-rendered once on appear, deterministic seed → same texture
/// every launch (no flicker between resizes).
struct GrainOverlay: View {
    var intensity: Double = 0.05
    var dotsPerPx: Double = 0.0006  // ~600 dots in a 1000×1000 area

    var body: some View {
        Canvas { ctx, size in
            let count = Int(Double(size.width * size.height) * dotsPerPx)
            var rng = SeedableRNG(seed: 1337)
            for _ in 0..<count {
                let x = Double(rng.nextUInt() % UInt32(max(1, size.width)))
                let y = Double(rng.nextUInt() % UInt32(max(1, size.height)))
                let a = intensity * 0.4 + intensity * Double(rng.nextUInt() % 100) / 100.0
                let rect = CGRect(x: x, y: y, width: 1, height: 1)
                ctx.fill(Path(rect), with: .color(.white.opacity(a)))
            }
        }
        .blendMode(.overlay)
        .allowsHitTesting(false)
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

extension View {
    /// Adds a non-interactive grain overlay on top of the view. Apply
    /// once per surface (window root, sheet, panel) where gradient
    /// banding would otherwise show.
    func grainOverlay(intensity: Double = 0.05) -> some View {
        overlay(GrainOverlay(intensity: intensity))
    }
}
