import SwiftUI

/// 3D perspektif yatay carousel (#127). Ortadaki kart düz, kenarlardakiler
/// y-ekseninde dönerek küçülür ve solar. Container'ın gerçek genişliğine göre
/// hesaplandığı için pencere boyutuna ve ekrana bağımsız çalışır.
struct Carousel3DGallery: View {
    let wallpapers: [Wallpaper]
    var onTap: ((Wallpaper) -> Void)? = nil

    private let cardWidth: CGFloat = 280
    private let cardHeight: CGFloat = 200
    private let spacing: CGFloat = -40       // overlap so depth illusion holds
    private let maxAngle: Double = 38
    private let maxScaleLoss: Double = 0.22
    private let minOpacity: Double = 0.35
    private let coordSpace = "carousel3d"

    var body: some View {
        GeometryReader { container in
            let centerX = container.size.width / 2
            let leadingPad = max(centerX - cardWidth / 2, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: spacing) {
                    ForEach(wallpapers, id: \.id) { wallpaper in
                        card(for: wallpaper, centerX: centerX)
                    }
                }
                .padding(.horizontal, leadingPad)
                .padding(.vertical, 24)
            }
            .coordinateSpace(name: coordSpace)
        }
        .frame(height: cardHeight + 48)
    }

    @ViewBuilder
    private func card(for wallpaper: Wallpaper, centerX: CGFloat) -> some View {
        GeometryReader { card in
            let cardCenter = card.frame(in: .named(coordSpace)).midX
            let raw = (cardCenter - centerX) / 320
            let clamped = max(-1.4, min(1.4, raw))
            let angle = clamped * maxAngle
            let scale = max(0.66, 1.0 - abs(clamped) * maxScaleLoss)
            let opacity = max(minOpacity, 1.0 - abs(clamped) * 0.55)
            let z = 1.0 - abs(clamped)

            CarouselCard(wallpaper: wallpaper)
                .frame(width: cardWidth, height: cardHeight)
                .scaleEffect(scale)
                .rotation3DEffect(
                    .degrees(-angle),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.6
                )
                .opacity(opacity)
                .zIndex(z)
                .onTapGesture {
                    onTap?(wallpaper)
                }
        }
        .frame(width: cardWidth, height: cardHeight)
    }
}
