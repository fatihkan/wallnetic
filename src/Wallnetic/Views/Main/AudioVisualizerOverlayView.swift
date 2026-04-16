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

        // Bloom pass — heavier blur for explosion glow.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 14))
            layer.opacity = 0.6
            drawBurst(context: layer, size: size, centerX: centerX, bands: bands, accent: accent)
        }

        // Sharp pass.
        drawBurst(context: context, size: size, centerX: centerX, bands: bands, accent: accent)

        drawCenterLine(context: context, size: size, centerX: centerX, accent: accent, loudness: loud)
    }

    // MARK: - Background

    private func drawBackground(context: GraphicsContext, size: CGSize, centerX: CGFloat, accent: Color, loudness: CGFloat) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(Path(roundedRect: rect, cornerRadius: 18), with: .color(.black.opacity(0.5)))

        // Pulsing center glow.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 35))
            layer.opacity = 0.35 + Double(loudness) * 0.45
            layer.fill(
                Path(ellipseIn: CGRect(
                    x: centerX - 100,
                    y: size.height / 2 - 70,
                    width: 200,
                    height: 140
                )),
                with: .color(accent.opacity(0.7))
            )
        }
    }

    // MARK: - Horizontal burst

    private func drawBurst(context: GraphicsContext, size: CGSize, centerX: CGFloat, bands: [Float], accent: Color) {
        let verticalInset: CGFloat = 8
        let horizontalInset: CGFloat = 10
        let bandCount = bands.count
        let rowSpacing: CGFloat = 1
        let usableHeight = size.height - verticalInset * 2
        let rowHeight = max(2, (usableHeight - rowSpacing * CGFloat(bandCount - 1)) / CGFloat(bandCount))

        let tileWidth: CGFloat = 4
        let tileGap: CGFloat = 1.5
        let tilePitch = tileWidth + tileGap
        let halfWidth = centerX - horizontalInset
        let maxTiles = max(1, Int(halfWidth / tilePitch))
        let centerGap: CGFloat = 3

        // Precompute hot tip color (accent shifted toward white/warm).
        let tipColor = Color.white

        for (i, value) in bands.enumerated() {
            let y = verticalInset + CGFloat(i) * (rowHeight + rowSpacing)
            let amplitude = max(0.03, CGFloat(value))
            let litTiles = max(1, Int(round(amplitude * CGFloat(maxTiles))))

            // Higher amplitude → tiles get slightly taller for burst feel.
            let dynHeight = rowHeight + amplitude * 2

            for tile in 0..<litTiles {
                let progress = Double(tile) / Double(max(litTiles - 1, 1)) // 0 = center, 1 = tip

                // Color transition: accent at center → bright tip at edges.
                let baseAlpha = 0.9 - progress * 0.15
                let tipMix = progress * progress // accelerate toward tip
                let tileColor = blendColor(accent, tipColor, mix: tipMix, alpha: baseAlpha)

                let offset = centerGap + tilePitch * CGFloat(tile)

                // Right tile.
                let rightRect = CGRect(
                    x: centerX + offset,
                    y: y - (dynHeight - rowHeight) / 2,
                    width: tileWidth,
                    height: dynHeight
                )
                context.fill(Path(roundedRect: rightRect, cornerRadius: 1.5), with: .color(tileColor))

                // Left tile (mirror).
                let leftRect = CGRect(
                    x: centerX - offset - tileWidth,
                    y: y - (dynHeight - rowHeight) / 2,
                    width: tileWidth,
                    height: dynHeight
                )
                context.fill(Path(roundedRect: leftRect, cornerRadius: 1.5), with: .color(tileColor))
            }
        }
    }

    /// Blend two SwiftUI colors by mixing their resolved RGBA values.
    private func blendColor(_ a: Color, _ b: Color, mix t: Double, alpha: Double) -> Color {
        let resolved = NSColor(a).usingColorSpace(.sRGB)
        let rA = resolved?.redComponent ?? 0
        let gA = resolved?.greenComponent ?? 0
        let bA = resolved?.blueComponent ?? 0

        let resolvedB = NSColor(b).usingColorSpace(.sRGB)
        let rB = resolvedB?.redComponent ?? 1
        let gB = resolvedB?.greenComponent ?? 1
        let bB = resolvedB?.blueComponent ?? 1

        let clamped = max(0, min(1, t))
        return Color(
            red: Double(rA) + (Double(rB) - Double(rA)) * clamped,
            green: Double(gA) + (Double(gB) - Double(gA)) * clamped,
            blue: Double(bA) + (Double(bB) - Double(bA)) * clamped,
            opacity: alpha
        )
    }

    // MARK: - Center line

    private func drawCenterLine(context: GraphicsContext, size: CGSize, centerX: CGFloat, accent: Color, loudness: CGFloat) {
        // Glow.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 5))
            let lineRect = CGRect(x: centerX - 1.5, y: 4, width: 3, height: size.height - 8)
            layer.fill(
                Path(roundedRect: lineRect, cornerRadius: 1.5),
                with: .color(accent.opacity(0.6 + Double(loudness) * 0.3))
            )
        }

        // Sharp.
        let lineRect = CGRect(x: centerX - 0.5, y: 4, width: 1, height: size.height - 8)
        context.fill(
            Path(roundedRect: lineRect, cornerRadius: 0.5),
            with: .color(.white.opacity(0.85))
        )
    }
}
