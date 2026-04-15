import SwiftUI

struct AudioVisualizerOverlayView: View {
    @EnvironmentObject var manager: AudioVisualizerManager
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Canvas { ctx, size in
            let bands = manager.bands
            guard !bands.isEmpty else { return }

            let spacing: CGFloat = 4
            let totalSpacing = spacing * CGFloat(bands.count - 1)
            let barWidth = max(1, (size.width - totalSpacing) / CGFloat(bands.count))
            let maxHeight = size.height

            let baseColor = theme.accentColor
            let topColor = baseColor.opacity(0.9)
            let bottomColor = baseColor.opacity(0.35)

            for (i, value) in bands.enumerated() {
                let x = CGFloat(i) * (barWidth + spacing)
                let h = max(2, CGFloat(value) * maxHeight)
                let rect = CGRect(x: x, y: size.height - h, width: barWidth, height: h)
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                ctx.fill(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [topColor, bottomColor]),
                        startPoint: CGPoint(x: 0, y: rect.minY),
                        endPoint: CGPoint(x: 0, y: rect.maxY)
                    )
                )
            }
        }
        .shadow(color: theme.accentColor.opacity(0.4), radius: 8)
        .drawingGroup()
    }
}
