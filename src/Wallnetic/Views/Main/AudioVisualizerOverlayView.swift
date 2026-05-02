import SwiftUI

struct AudioVisualizerOverlayView: View {
    @EnvironmentObject var manager: AudioVisualizerManager
    @ObservedObject private var theme = ThemeManager.shared

    // Cached accent RGB — avoids NSColor conversion every frame at 60fps.
    @State private var accentRGB: (r: Double, g: Double, b: Double) = (0, 0, 0)

    var body: some View {
        Canvas(rendersAsynchronously: true) { ctx, size in
            draw(context: ctx, size: size)
        }
        .animation(.linear(duration: 1.0 / 60.0), value: manager.bands)
        .drawingGroup()
        .onChange(of: theme.accentColor.description) { _ in
            updateAccentRGB()
        }
        .onAppear {
            updateAccentRGB()
        }
    }

    private func updateAccentRGB() {
        let ns = NSColor(theme.accentColor).usingColorSpace(.sRGB)
        accentRGB = (
            r: Double(ns?.redComponent ?? 0),
            g: Double(ns?.greenComponent ?? 0),
            b: Double(ns?.blueComponent ?? 0)
        )
    }

    private func draw(context: GraphicsContext, size: CGSize) {
        let bands = manager.bands
        guard !bands.isEmpty else { return }

        let accent = theme.accentColor
        let loud = CGFloat(manager.loudness)
        let centerY = size.height / 2

        drawBackground(context: context, size: size, centerY: centerY, accent: accent, loudness: loud)

        switch manager.style {
        case .bars:
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 10))
                layer.opacity = 0.55
                drawBurst(context: layer, size: size, centerY: centerY, bands: bands, accent: accent)
            }
            drawBurst(context: context, size: size, centerY: centerY, bands: bands, accent: accent)
            drawCenterLine(context: context, size: size, centerY: centerY, accent: accent, loudness: loud)

        case .waveform:
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 8))
                layer.opacity = 0.6
                drawWaveform(context: layer, size: size, centerY: centerY, bands: bands, accent: accent)
            }
            drawWaveform(context: context, size: size, centerY: centerY, bands: bands, accent: accent)

        case .dots:
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 6))
                layer.opacity = 0.5
                drawDots(context: layer, size: size, centerY: centerY, bands: bands, accent: accent)
            }
            drawDots(context: context, size: size, centerY: centerY, bands: bands, accent: accent)
        }
    }

    // MARK: - Style: Waveform — mirrored continuous line driven by band amplitudes

    private func drawWaveform(context: GraphicsContext, size: CGSize, centerY: CGFloat, bands: [Float], accent: Color) {
        let inset: CGFloat = 8
        let usableWidth = size.width - inset * 2
        let halfHeight = centerY - 6
        let count = bands.count
        guard count > 1 else { return }

        var topPath = Path()
        var bottomPath = Path()

        for (i, value) in bands.enumerated() {
            let x = inset + CGFloat(i) / CGFloat(count - 1) * usableWidth
            let amplitude = max(0.0, CGFloat(value)) * halfHeight
            let yTop = centerY - amplitude
            let yBottom = centerY + amplitude

            if i == 0 {
                topPath.move(to: CGPoint(x: x, y: yTop))
                bottomPath.move(to: CGPoint(x: x, y: yBottom))
            } else {
                topPath.addLine(to: CGPoint(x: x, y: yTop))
                bottomPath.addLine(to: CGPoint(x: x, y: yBottom))
            }
        }

        context.stroke(topPath, with: .color(accent.opacity(0.95)), lineWidth: 1.6)
        context.stroke(bottomPath, with: .color(accent.opacity(0.95)), lineWidth: 1.6)

        // Center line for context
        let line = CGRect(x: inset, y: centerY - 0.5, width: usableWidth, height: 1)
        context.fill(Path(roundedRect: line, cornerRadius: 0.5), with: .color(.white.opacity(0.35)))
    }

    // MARK: - Style: Dots — sparse circular dot grid lit by amplitude

    private func drawDots(context: GraphicsContext, size: CGSize, centerY: CGFloat, bands: [Float], accent: Color) {
        let inset: CGFloat = 10
        let usableWidth = size.width - inset * 2
        let halfHeight = centerY - 8
        let dotRadius: CGFloat = 1.6
        let dotPitch: CGFloat = 6
        let maxDots = max(1, Int(halfHeight / dotPitch))

        let acR = accentRGB.r
        let acG = accentRGB.g
        let acB = accentRGB.b

        let count = bands.count
        for (i, value) in bands.enumerated() {
            let x = inset + CGFloat(i) / CGFloat(max(count - 1, 1)) * usableWidth
            let amplitude = max(0.0, CGFloat(value))
            let litDots = max(1, Int(round(amplitude * CGFloat(maxDots))))

            for d in 0..<litDots {
                let progress = Double(d) / Double(max(litDots - 1, 1))
                let tipMix = progress * progress
                let alpha = 0.85 - progress * 0.3
                let r = acR + (1.0 - acR) * tipMix
                let g = acG + (1.0 - acG) * tipMix
                let b = acB + (1.0 - acB) * tipMix
                let color = Color(red: r, green: g, blue: b, opacity: alpha)

                let offset = CGFloat(d) * dotPitch + 4
                let topY = centerY - offset
                let bottomY = centerY + offset
                let topRect = CGRect(x: x - dotRadius, y: topY - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
                let bottomRect = CGRect(x: x - dotRadius, y: bottomY - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
                context.fill(Path(ellipseIn: topRect), with: .color(color))
                context.fill(Path(ellipseIn: bottomRect), with: .color(color))
            }
        }
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

        let acR = accentRGB.r
        let acG = accentRGB.g
        let acB = accentRGB.b

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
