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
        let centerY = size.height / 2

        drawBackground(context: context, size: size, centerY: centerY, accent: accent, loudness: loud)

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 10))
            layer.opacity = 0.55
            drawBurst(context: layer, size: size, centerY: centerY, bands: bands, accent: accent)
        }

        drawBurst(context: context, size: size, centerY: centerY, bands: bands, accent: accent)

        drawCenterLine(context: context, size: size, centerY: centerY, accent: accent, loudness: loud)
    }

    // MARK: - Background

    private func drawBackground(context: GraphicsContext, size: CGSize, centerY: CGFloat, accent: Color, loudness: CGFloat) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(Path(roundedRect: rect, cornerRadius: 16), with: .color(.black.opacity(0.5)))

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 30))
            layer.opacity = 0.3 + Double(loudness) * 0.45
            layer.fill(
                Path(ellipseIn: CGRect(
                    x: size.width / 2 - 130,
                    y: centerY - 40,
                    width: 260, height: 80
                )),
                with: .color(accent.opacity(0.65))
            )
        }
    }

    // MARK: - Bars: 64 columns, tiles burst UP + DOWN from center

    private func drawBurst(context: GraphicsContext, size: CGSize, centerY: CGFloat, bands: [Float], accent: Color) {
        let horizontalInset: CGFloat = 8
        let verticalInset: CGFloat = 6
        let bandCount = bands.count
        let barSpacing: CGFloat = 1
        let usableWidth = size.width - horizontalInset * 2
        let barWidth = max(1.5, (usableWidth - barSpacing * CGFloat(bandCount - 1)) / CGFloat(bandCount))

        let tileHeight: CGFloat = 2
        let tileGap: CGFloat = 1
        let tilePitch = tileHeight + tileGap
        let halfHeight = centerY - verticalInset
        let maxTiles = max(1, Int(halfHeight / tilePitch))
        let centerGap: CGFloat = 1.5

        let nsAccent = NSColor(accent).usingColorSpace(.sRGB)
        let acR = Double(nsAccent?.redComponent ?? 0)
        let acG = Double(nsAccent?.greenComponent ?? 0)
        let acB = Double(nsAccent?.blueComponent ?? 0)

        for (i, value) in bands.enumerated() {
            let x = horizontalInset + CGFloat(i) * (barWidth + barSpacing)
            let amplitude = max(0.03, CGFloat(value))
            let litTiles = max(1, Int(round(amplitude * CGFloat(maxTiles))))

            for tile in 0..<litTiles {
                let progress = Double(tile) / Double(max(litTiles - 1, 1))
                let tipMix = progress * progress * progress
                let alpha = 0.88 - progress * 0.2

                let r = acR + (1.0 - acR) * tipMix
                let g = acG + (1.0 - acG) * tipMix
                let b = acB + (1.0 - acB) * tipMix
                let tileColor = Color(red: r, green: g, blue: b, opacity: alpha)

                let offset = centerGap + tilePitch * CGFloat(tile)

                // Up.
                let topRect = CGRect(x: x, y: centerY - offset - tileHeight, width: barWidth, height: tileHeight)
                context.fill(Path(roundedRect: topRect, cornerRadius: 0.5), with: .color(tileColor))

                // Down.
                let bottomRect = CGRect(x: x, y: centerY + offset, width: barWidth, height: tileHeight)
                context.fill(Path(roundedRect: bottomRect, cornerRadius: 0.5), with: .color(tileColor))
            }
        }
    }

    // MARK: - Center line (horizontal)

    private func drawCenterLine(context: GraphicsContext, size: CGSize, centerY: CGFloat, accent: Color, loudness: CGFloat) {
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 4))
            let rect = CGRect(x: 4, y: centerY - 1, width: size.width - 8, height: 2)
            layer.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(accent.opacity(0.5 + Double(loudness) * 0.35)))
        }
        let rect = CGRect(x: 4, y: centerY - 0.5, width: size.width - 8, height: 1)
        context.fill(Path(roundedRect: rect, cornerRadius: 0.5), with: .color(.white.opacity(0.8)))
    }
}
