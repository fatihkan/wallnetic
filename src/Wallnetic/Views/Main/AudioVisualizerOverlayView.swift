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
        guard !bands.isEmpty else { return }

        let accent = theme.accentColor
        let loud = CGFloat(manager.loudness)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        drawBackground(context: context, size: size, center: center, accent: accent, loudness: loud)

        // Bloom pass.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 10))
            layer.opacity = 0.7
            drawRadialBars(context: layer, size: size, center: center, bands: bands, accent: accent)
        }

        // Sharp pass.
        drawRadialBars(context: context, size: size, center: center, bands: bands, accent: accent)

        drawCenterRing(context: context, center: center, accent: accent, loudness: loud)
    }

    // MARK: - Background

    private func drawBackground(context: GraphicsContext, size: CGSize, center: CGPoint, accent: Color, loudness: CGFloat) {
        let rect = CGRect(origin: .zero, size: size)

        context.fill(Path(ellipseIn: rect), with: .color(.black.opacity(0.45)))

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 35))
            layer.opacity = 0.45 + Double(loudness) * 0.4
            layer.fill(
                Path(ellipseIn: rect.insetBy(dx: 30, dy: 30)),
                with: .radialGradient(
                    Gradient(colors: [
                        accent.opacity(0.6),
                        accent.opacity(0)
                    ]),
                    center: center,
                    startRadius: 0,
                    endRadius: min(size.width, size.height) * 0.4
                )
            )
        }
    }

    // MARK: - Radial bars

    private func drawRadialBars(context: GraphicsContext, size: CGSize, center: CGPoint, bands: [Float], accent: Color) {
        let bandCount = bands.count
        let innerRadius: CGFloat = min(size.width, size.height) * 0.14
        let maxBarLength: CGFloat = min(size.width, size.height) * 0.32
        let barWidth: CGFloat = 4
        let tileHeight: CGFloat = 3
        let tileGap: CGFloat = 1.5
        let tilePitch = tileHeight + tileGap
        let maxTiles = max(1, Int(maxBarLength / tilePitch))

        let angleStep = (2 * CGFloat.pi) / CGFloat(bandCount)

        for (i, value) in bands.enumerated() {
            let angle = angleStep * CGFloat(i) - CGFloat.pi / 2  // Start from top
            let amplitude = max(0.05, CGFloat(value))
            let litTiles = max(1, Int(round(amplitude * CGFloat(maxTiles))))

            let cosA = cos(angle)
            let sinA = sin(angle)

            for tile in 0..<litTiles {
                let dist = innerRadius + tilePitch * CGFloat(tile)
                let tileCenter = CGPoint(
                    x: center.x + cosA * (dist + tileHeight / 2),
                    y: center.y + sinA * (dist + tileHeight / 2)
                )

                let t = Double(tile) / Double(maxTiles)
                let alpha = 0.95 - t * 0.35

                var tileCtx = context
                tileCtx.translateBy(x: tileCenter.x, y: tileCenter.y)
                tileCtx.rotate(by: Angle(radians: Double(angle) + .pi / 2))

                let rect = CGRect(
                    x: -barWidth / 2,
                    y: -tileHeight / 2,
                    width: barWidth,
                    height: tileHeight
                )
                tileCtx.fill(
                    Path(roundedRect: rect, cornerRadius: 1),
                    with: .color(accent.opacity(alpha))
                )
            }
        }
    }

    // MARK: - Center ring

    private func drawCenterRing(context: GraphicsContext, center: CGPoint, accent: Color, loudness: CGFloat) {
        let baseRadius: CGFloat = 18
        let pulseRadius = baseRadius + loudness * 4

        // Inner glow.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 8))
            let glowRect = CGRect(
                x: center.x - pulseRadius - 8,
                y: center.y - pulseRadius - 8,
                width: (pulseRadius + 8) * 2,
                height: (pulseRadius + 8) * 2
            )
            layer.fill(
                Path(ellipseIn: glowRect),
                with: .color(accent.opacity(0.35 + Double(loudness) * 0.3))
            )
        }

        // Ring stroke.
        let ringRect = CGRect(
            x: center.x - pulseRadius,
            y: center.y - pulseRadius,
            width: pulseRadius * 2,
            height: pulseRadius * 2
        )
        context.stroke(
            Path(ellipseIn: ringRect),
            with: .color(accent.opacity(0.8)),
            lineWidth: 1.5
        )

        // Inner dot.
        let dotSize: CGFloat = 4
        let dotRect = CGRect(
            x: center.x - dotSize / 2,
            y: center.y - dotSize / 2,
            width: dotSize,
            height: dotSize
        )
        context.fill(Path(ellipseIn: dotRect), with: .color(accent.opacity(0.9)))
    }
}
