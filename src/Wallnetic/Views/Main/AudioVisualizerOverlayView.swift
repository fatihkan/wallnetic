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

        // Bloom.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 12))
            layer.opacity = 0.6
            drawBurst(context: layer, size: size, centerY: centerY, bands: bands, accent: accent)
        }

        // Sharp.
        drawBurst(context: context, size: size, centerY: centerY, bands: bands, accent: accent)

        drawCenterLine(context: context, size: size, centerY: centerY, accent: accent, loudness: loud)
    }

    // MARK: - Background

    private func drawBackground(context: GraphicsContext, size: CGSize, centerY: CGFloat, accent: Color, loudness: CGFloat) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(Path(roundedRect: rect, cornerRadius: 18), with: .color(.black.opacity(0.5)))

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 35))
            layer.opacity = 0.35 + Double(loudness) * 0.45
            layer.fill(
                Path(ellipseIn: CGRect(
                    x: size.width / 2 - 120,
                    y: centerY - 50,
                    width: 240,
                    height: 100
                )),
                with: .color(accent.opacity(0.7))
            )
        }
    }

    // MARK: - Vertical burst bars (arranged horizontally)

    private func drawBurst(context: GraphicsContext, size: CGSize, centerY: CGFloat, bands: [Float], accent: Color) {
        let horizontalInset: CGFloat = 12
        let verticalInset: CGFloat = 8
        let bandCount = bands.count
        let barSpacing: CGFloat = 3
        let usableWidth = size.width - horizontalInset * 2
        let barWidth = max(3, (usableWidth - barSpacing * CGFloat(bandCount - 1)) / CGFloat(bandCount))

        let tileHeight: CGFloat = 3
        let tileGap: CGFloat = 1.5
        let tilePitch = tileHeight + tileGap
        let halfHeight = centerY - verticalInset
        let maxTiles = max(1, Int(halfHeight / tilePitch))
        let centerGap: CGFloat = 2

        let tipColor = Color.white

        for (i, value) in bands.enumerated() {
            let x = horizontalInset + CGFloat(i) * (barWidth + barSpacing)
            let amplitude = max(0.04, CGFloat(value))
            let litTiles = max(1, Int(round(amplitude * CGFloat(maxTiles))))

            // Louder bars get slightly wider for burst feel.
            let dynWidth = barWidth + amplitude * 2
            let xOffset = (dynWidth - barWidth) / 2

            for tile in 0..<litTiles {
                let progress = Double(tile) / Double(max(litTiles - 1, 1))
                let tipMix = progress * progress
                let baseAlpha = 0.92 - progress * 0.15
                let tileColor = blendColor(accent, tipColor, mix: tipMix, alpha: baseAlpha)

                let offset = centerGap + tilePitch * CGFloat(tile)

                // Top (upward from center).
                let topRect = CGRect(
                    x: x - xOffset,
                    y: centerY - offset - tileHeight,
                    width: dynWidth,
                    height: tileHeight
                )
                context.fill(Path(roundedRect: topRect, cornerRadius: 1.5), with: .color(tileColor))

                // Bottom (downward mirror).
                let bottomRect = CGRect(
                    x: x - xOffset,
                    y: centerY + offset,
                    width: dynWidth,
                    height: tileHeight
                )
                context.fill(Path(roundedRect: bottomRect, cornerRadius: 1.5), with: .color(tileColor))
            }
        }
    }

    private func blendColor(_ a: Color, _ b: Color, mix t: Double, alpha: Double) -> Color {
        let ra = NSColor(a).usingColorSpace(.sRGB)
        let rb = NSColor(b).usingColorSpace(.sRGB)
        let rA = Double(ra?.redComponent ?? 0)
        let gA = Double(ra?.greenComponent ?? 0)
        let bA = Double(ra?.blueComponent ?? 0)
        let rB = Double(rb?.redComponent ?? 1)
        let gB = Double(rb?.greenComponent ?? 1)
        let bB = Double(rb?.blueComponent ?? 1)
        let c = max(0, min(1, t))
        return Color(
            red: rA + (rB - rA) * c,
            green: gA + (gB - gA) * c,
            blue: bA + (bB - bA) * c,
            opacity: alpha
        )
    }

    // MARK: - Center line

    private func drawCenterLine(context: GraphicsContext, size: CGSize, centerY: CGFloat, accent: Color, loudness: CGFloat) {
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 5))
            let rect = CGRect(x: 4, y: centerY - 1.5, width: size.width - 8, height: 3)
            layer.fill(Path(roundedRect: rect, cornerRadius: 1.5),
                        with: .color(accent.opacity(0.6 + Double(loudness) * 0.3)))
        }
        let rect = CGRect(x: 4, y: centerY - 0.5, width: size.width - 8, height: 1)
        context.fill(Path(roundedRect: rect, cornerRadius: 0.5),
                      with: .color(.white.opacity(0.85)))
    }
}
