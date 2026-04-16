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

        // Bloom.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 10))
            layer.opacity = 0.55
            drawBurst(context: layer, size: size, centerX: centerX, bands: bands, accent: accent)
        }

        // Sharp.
        drawBurst(context: context, size: size, centerX: centerX, bands: bands, accent: accent)

        drawCenterLine(context: context, size: size, centerX: centerX, accent: accent, loudness: loud)
    }

    // MARK: - Background

    private func drawBackground(context: GraphicsContext, size: CGSize, centerX: CGFloat, accent: Color, loudness: CGFloat) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(Path(roundedRect: rect, cornerRadius: 16), with: .color(.black.opacity(0.5)))

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 30))
            layer.opacity = 0.3 + Double(loudness) * 0.45
            layer.fill(
                Path(ellipseIn: CGRect(
                    x: centerX - 60,
                    y: size.height / 2 - 60,
                    width: 120,
                    height: 120
                )),
                with: .color(accent.opacity(0.65))
            )
        }
    }

    // MARK: - Horizontal burst (tiles go left + right from center)

    private func drawBurst(context: GraphicsContext, size: CGSize, centerX: CGFloat, bands: [Float], accent: Color) {
        let verticalInset: CGFloat = 6
        let horizontalInset: CGFloat = 8
        let bandCount = bands.count
        let rowSpacing: CGFloat = 0.5
        let usableHeight = size.height - verticalInset * 2
        let rowHeight = max(1, (usableHeight - rowSpacing * CGFloat(bandCount - 1)) / CGFloat(bandCount))

        let tileWidth: CGFloat = 2.5
        let tileGap: CGFloat = 1
        let tilePitch = tileWidth + tileGap
        let halfWidth = centerX - horizontalInset
        let maxTiles = max(1, Int(halfWidth / tilePitch))
        let centerGap: CGFloat = 1.5

        // Precompute accent RGB once.
        let nsAccent = NSColor(accent).usingColorSpace(.sRGB)
        let acR = Double(nsAccent?.redComponent ?? 0)
        let acG = Double(nsAccent?.greenComponent ?? 0)
        let acB = Double(nsAccent?.blueComponent ?? 0)

        for (i, value) in bands.enumerated() {
            let y = verticalInset + CGFloat(i) * (rowHeight + rowSpacing)
            let amplitude = max(0.03, CGFloat(value))
            let litTiles = max(1, Int(round(amplitude * CGFloat(maxTiles))))

            for tile in 0..<litTiles {
                let progress = Double(tile) / Double(max(litTiles - 1, 1))

                // Cubic easing — accent longer, white only at tip.
                let tipMix = progress * progress * progress
                let alpha = 0.88 - progress * 0.2

                let r = acR + (1.0 - acR) * tipMix
                let g = acG + (1.0 - acG) * tipMix
                let b = acB + (1.0 - acB) * tipMix
                let tileColor = Color(red: r, green: g, blue: b, opacity: alpha)

                let offset = centerGap + tilePitch * CGFloat(tile)

                // Right.
                let rightRect = CGRect(x: centerX + offset, y: y, width: tileWidth, height: rowHeight)
                context.fill(Path(roundedRect: rightRect, cornerRadius: 0.5), with: .color(tileColor))

                // Left.
                let leftRect = CGRect(x: centerX - offset - tileWidth, y: y, width: tileWidth, height: rowHeight)
                context.fill(Path(roundedRect: leftRect, cornerRadius: 0.5), with: .color(tileColor))
            }
        }
    }

    // MARK: - Center line

    private func drawCenterLine(context: GraphicsContext, size: CGSize, centerX: CGFloat, accent: Color, loudness: CGFloat) {
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 4))
            let rect = CGRect(x: centerX - 1, y: 4, width: 2, height: size.height - 8)
            layer.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(accent.opacity(0.5 + Double(loudness) * 0.35)))
        }
        let rect = CGRect(x: centerX - 0.5, y: 4, width: 1, height: size.height - 8)
        context.fill(Path(roundedRect: rect, cornerRadius: 0.5), with: .color(.white.opacity(0.8)))
    }
}
