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

        drawBackground(context: context, size: size, accent: accent, loudness: loud)

        // Neon bloom pass — same bars drawn into a blurred layer for the glow.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 12))
            layer.opacity = 0.75
            drawBars(context: layer, size: size, bands: bands, accent: accent)
        }

        // Sharp pass on top.
        drawBars(context: context, size: size, bands: bands, accent: accent)
    }

    // MARK: - Background

    private func drawBackground(context: GraphicsContext, size: CGSize, accent: Color, loudness: CGFloat) {
        let radius: CGFloat = 28
        let rect = CGRect(origin: .zero, size: size)
        let path = Path(roundedRect: rect, cornerRadius: radius)

        // Deep dark base so neon bars pop.
        context.fill(path, with: .color(.black.opacity(0.55)))

        // Center glow tinted with the accent.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 40))
            layer.opacity = 0.55 + Double(loudness) * 0.35
            layer.fill(
                path,
                with: .radialGradient(
                    Gradient(colors: [
                        accent.opacity(0.55),
                        accent.opacity(0)
                    ]),
                    center: CGPoint(x: size.width / 2, y: size.height / 2),
                    startRadius: 0,
                    endRadius: size.width * 0.5
                )
            )
        }
    }

    // MARK: - Bars (segmented / LED-meter style)

    private func drawBars(context: GraphicsContext, size: CGSize, bands: [Float], accent: Color) {
        let horizontalInset: CGFloat = 14
        let verticalInset: CGFloat = 10
        let bandCount = bands.count
        let spacing: CGFloat = 3
        let totalSpacing = spacing * CGFloat(bandCount - 1)
        let usableWidth = size.width - horizontalInset * 2
        let barWidth = max(3, (usableWidth - totalSpacing) / CGFloat(bandCount))
        let centerY = size.height / 2
        let halfHeight = centerY - verticalInset

        // Segment geometry — small horizontal tiles stacked to form each bar.
        let tileHeight: CGFloat = 3
        let tileGap: CGFloat = 1
        let tilePitch = tileHeight + tileGap
        let tilesPerSide = max(1, Int(halfHeight / tilePitch))

        for (i, value) in bands.enumerated() {
            let x = horizontalInset + CGFloat(i) * (barWidth + spacing)
            let amplitude = max(0.04, CGFloat(value))
            let litTiles = max(1, Int(round(amplitude * CGFloat(tilesPerSide))))

            // --- Top half ---
            for tile in 0..<litTiles {
                let tileY = centerY - tilePitch * CGFloat(tile + 1)
                let rect = CGRect(x: x, y: tileY, width: barWidth, height: tileHeight)

                // Brightness ramps down slightly toward the top so the tips feel hotter in the middle.
                let t = Double(tile) / Double(tilesPerSide)
                let alpha = 0.9 - t * 0.2
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1),
                    with: .color(accent.opacity(alpha))
                )
            }

            // --- Mirror reflection ---
            for tile in 0..<litTiles {
                let tileY = centerY + tilePitch * CGFloat(tile)
                let rect = CGRect(x: x, y: tileY, width: barWidth, height: tileHeight)

                // Reflection fades quickly with distance from baseline.
                let t = Double(tile) / Double(tilesPerSide)
                let alpha = 0.6 * (1 - t * 1.4)
                if alpha <= 0 { break }
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1),
                    with: .color(accent.opacity(alpha))
                )
            }
        }

        // Baseline — bright horizontal line that sells the "mirror" effect.
        let baseline = Path { path in
            let y = centerY - 0.5
            path.addRect(CGRect(x: horizontalInset, y: y, width: size.width - horizontalInset * 2, height: 1))
        }
        context.fill(baseline, with: .color(accent.opacity(0.9)))
    }
}
