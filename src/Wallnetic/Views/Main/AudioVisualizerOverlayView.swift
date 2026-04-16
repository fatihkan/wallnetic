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
        let centerX = size.width / 2

        drawBackground(context: context, size: size, centerX: centerX, accent: accent, loudness: loud)

        // Bloom pass.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 10))
            layer.opacity = 0.65
            drawHorizontalBars(context: layer, size: size, centerX: centerX, bands: bands, accent: accent)
        }

        // Sharp pass.
        drawHorizontalBars(context: context, size: size, centerX: centerX, bands: bands, accent: accent)

        // Center line.
        drawCenterLine(context: context, size: size, centerX: centerX, accent: accent, loudness: loud)
    }

    // MARK: - Background

    private func drawBackground(context: GraphicsContext, size: CGSize, centerX: CGFloat, accent: Color, loudness: CGFloat) {
        let rect = CGRect(origin: .zero, size: size)
        let path = Path(roundedRect: rect, cornerRadius: 20)

        context.fill(path, with: .color(.black.opacity(0.5)))

        // Center glow that pulses.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 30))
            layer.opacity = 0.4 + Double(loudness) * 0.4
            layer.fill(
                Path(ellipseIn: CGRect(
                    x: centerX - 80,
                    y: size.height / 2 - 60,
                    width: 160,
                    height: 120
                )),
                with: .color(accent.opacity(0.6))
            )
        }
    }

    // MARK: - Horizontal bars (center-out)

    private func drawHorizontalBars(context: GraphicsContext, size: CGSize, centerX: CGFloat, bands: [Float], accent: Color) {
        let verticalInset: CGFloat = 10
        let horizontalInset: CGFloat = 12
        let bandCount = bands.count
        let rowSpacing: CGFloat = 2
        let usableHeight = size.height - verticalInset * 2
        let rowHeight = max(2, (usableHeight - rowSpacing * CGFloat(bandCount - 1)) / CGFloat(bandCount))

        let tileWidth: CGFloat = 3
        let tileGap: CGFloat = 1.5
        let tilePitch = tileWidth + tileGap
        let halfWidth = centerX - horizontalInset
        let maxTiles = max(1, Int(halfWidth / tilePitch))

        // Small gap at the center so tiles don't stack on the line.
        let centerGap: CGFloat = 2

        for (i, value) in bands.enumerated() {
            let y = verticalInset + CGFloat(i) * (rowHeight + rowSpacing)
            let amplitude = max(0.04, CGFloat(value))
            let litTiles = max(1, Int(round(amplitude * CGFloat(maxTiles))))

            for tile in 0..<litTiles {
                let t = Double(tile) / Double(maxTiles)
                let alpha = 0.92 - t * 0.4

                let offset = centerGap + tilePitch * CGFloat(tile)

                // Right side.
                let rightRect = CGRect(
                    x: centerX + offset,
                    y: y,
                    width: tileWidth,
                    height: rowHeight
                )
                context.fill(
                    Path(roundedRect: rightRect, cornerRadius: 1),
                    with: .color(accent.opacity(alpha))
                )

                // Left side (mirror).
                let leftRect = CGRect(
                    x: centerX - offset - tileWidth,
                    y: y,
                    width: tileWidth,
                    height: rowHeight
                )
                context.fill(
                    Path(roundedRect: leftRect, cornerRadius: 1),
                    with: .color(accent.opacity(alpha))
                )
            }
        }
    }

    // MARK: - Center line

    private func drawCenterLine(context: GraphicsContext, size: CGSize, centerX: CGFloat, accent: Color, loudness: CGFloat) {
        // Glowing center axis.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 4))
            let lineRect = CGRect(x: centerX - 1, y: 6, width: 2, height: size.height - 12)
            layer.fill(
                Path(roundedRect: lineRect, cornerRadius: 1),
                with: .color(accent.opacity(0.5 + Double(loudness) * 0.3))
            )
        }

        // Sharp center line.
        let lineRect = CGRect(x: centerX - 0.5, y: 6, width: 1, height: size.height - 12)
        context.fill(
            Path(roundedRect: lineRect, cornerRadius: 0.5),
            with: .color(accent.opacity(0.85))
        )
    }
}
