import SwiftUI

struct AudioVisualizerOverlayView: View {
    @EnvironmentObject var manager: AudioVisualizerManager
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Canvas(rendersAsynchronously: true) { ctx, size in
            draw(context: ctx, size: size)
        }
        .animation(.linear(duration: 1.0 / 60.0), value: manager.bands)
        .drawingGroup()
    }

    private func draw(context: GraphicsContext, size: CGSize) {
        let bands = manager.bands
        let peaks = manager.peaks
        guard !bands.isEmpty else { return }

        let accent = theme.accentColor
        let loud = CGFloat(manager.loudness)

        drawBackgroundGlow(context: context, size: size, accent: accent, loudness: loud)
        drawBars(context: context, size: size, bands: bands, peaks: peaks, accent: accent, loudness: loud)
    }

    // MARK: - Background glow

    private func drawBackgroundGlow(context: GraphicsContext, size: CGSize, accent: Color, loudness: CGFloat) {
        let radius: CGFloat = 28
        let rect = CGRect(origin: .zero, size: size)
        let path = Path(roundedRect: rect, cornerRadius: radius)

        // Outer soft glow that pulses with overall loudness.
        var glow = context
        glow.addFilter(.blur(radius: 18))
        glow.fill(
            path,
            with: .radialGradient(
                Gradient(colors: [
                    accent.opacity(0.30 + 0.25 * loudness),
                    accent.opacity(0)
                ]),
                center: CGPoint(x: size.width / 2, y: size.height / 2),
                startRadius: 0,
                endRadius: max(size.width, size.height) * 0.7
            )
        )

        // Subtle vignette so the bars stand out even on bright wallpapers.
        context.fill(
            path,
            with: .linearGradient(
                Gradient(colors: [
                    .black.opacity(0.12),
                    .black.opacity(0.28)
                ]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )
    }

    // MARK: - Bars

    private func drawBars(
        context: GraphicsContext,
        size: CGSize,
        bands: [Float],
        peaks: [Float],
        accent: Color,
        loudness: CGFloat
    ) {
        let horizontalInset: CGFloat = 12
        let verticalInset: CGFloat = 8
        let bandCount = bands.count
        let spacing: CGFloat = 3
        let totalSpacing = spacing * CGFloat(bandCount - 1)
        let usableWidth = size.width - horizontalInset * 2
        let barWidth = max(2, (usableWidth - totalSpacing) / CGFloat(bandCount))
        let centerY = size.height / 2
        let maxTop = centerY - verticalInset
        let maxBottom = size.height - centerY - verticalInset

        // Gradient definitions
        let topGradient = Gradient(stops: [
            .init(color: accent.opacity(0.95), location: 0),
            .init(color: accent.opacity(0.75), location: 0.6),
            .init(color: accent.opacity(0.35), location: 1.0)
        ])
        let reflectionGradient = Gradient(stops: [
            .init(color: accent.opacity(0.55), location: 0),
            .init(color: accent.opacity(0.12), location: 0.6),
            .init(color: accent.opacity(0.0), location: 1.0)
        ])

        for (i, value) in bands.enumerated() {
            let x = horizontalInset + CGFloat(i) * (barWidth + spacing)

            // Ensure even at silence there's a sliver of a bar so the visualizer never looks dead.
            let floor: CGFloat = 0.04
            let amplitude = max(floor, CGFloat(value))
            let topHeight = amplitude * maxTop
            let bottomHeight = amplitude * maxBottom * 0.7 // reflection is shorter

            // Main bar (upward from center)
            let topRect = CGRect(
                x: x,
                y: centerY - topHeight,
                width: barWidth,
                height: topHeight
            )
            let topPath = Path(roundedRect: topRect, cornerRadius: barWidth / 2)
            context.fill(
                topPath,
                with: .linearGradient(
                    topGradient,
                    startPoint: CGPoint(x: 0, y: topRect.minY),
                    endPoint: CGPoint(x: 0, y: topRect.maxY)
                )
            )

            // Reflection (downward, fading)
            let bottomRect = CGRect(
                x: x,
                y: centerY,
                width: barWidth,
                height: bottomHeight
            )
            let bottomPath = Path(roundedRect: bottomRect, cornerRadius: barWidth / 2)
            context.fill(
                bottomPath,
                with: .linearGradient(
                    reflectionGradient,
                    startPoint: CGPoint(x: 0, y: bottomRect.minY),
                    endPoint: CGPoint(x: 0, y: bottomRect.maxY)
                )
            )

            // Peak-hold cap — small bright line that falls slowly.
            let peakValue = CGFloat(peaks[i])
            if peakValue > floor + 0.02 {
                let peakY = centerY - peakValue * maxTop
                let capRect = CGRect(
                    x: x,
                    y: max(verticalInset, peakY - 2),
                    width: barWidth,
                    height: 2
                )
                let cap = Path(roundedRect: capRect, cornerRadius: 1)
                context.fill(cap, with: .color(.white.opacity(0.85 + 0.15 * Double(loudness))))
            }
        }

        // Center hairline — subtle baseline so bars read as "reflecting" rather than floating.
        let baseline = Path { path in
            let y = centerY
            path.move(to: CGPoint(x: horizontalInset, y: y))
            path.addLine(to: CGPoint(x: size.width - horizontalInset, y: y))
        }
        context.stroke(baseline, with: .color(.white.opacity(0.12 + 0.1 * Double(loudness))), lineWidth: 0.5)
    }
}
