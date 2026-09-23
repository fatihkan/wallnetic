import SwiftUI

private struct GalleryScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// 3D perspektif yatay carousel (#127). Ortadaki kart düz, kenarlardakiler
/// y-ekseninde dönerek küçülür ve solar. Container'ın gerçek genişliğine göre
/// hesaplandığı için pencere boyutuna ve ekrana bağımsız çalışır.
struct Carousel3DGallery: View {
    let wallpapers: [Wallpaper]
    var onTap: ((Wallpaper) -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollOffset: CGFloat = 0
    @Namespace private var coordSpace

    private let cardWidth: CGFloat = 280
    private let cardHeight: CGFloat = 200
    private let spacing: CGFloat = -40       // overlap so depth illusion holds
    private let maxAngle: Double = 38
    private let maxScaleLoss: Double = 0.22
    private let minOpacity: Double = 0.35

    var body: some View {
        GeometryReader { container in
            let centerX = container.size.width / 2
            let leadingPad = max(centerX - cardWidth / 2, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: reduceMotion ? Space.md : spacing) {
                    ForEach(Array(wallpapers.enumerated()), id: \.element.id) { index, wallpaper in
                        card(for: wallpaper, index: index)
                    }
                }
                .padding(.horizontal, leadingPad)
                .padding(.vertical, 24)
                .background {
                    GeometryReader { content in
                        Color.clear.preference(
                            key: GalleryScrollOffsetKey.self,
                            value: content.frame(in: .named(coordSpace)).minX
                        )
                    }
                }
            }
            .coordinateSpace(name: coordSpace)
            .onPreferenceChange(GalleryScrollOffsetKey.self) { scrollOffset = $0 }
        }
        .frame(height: cardHeight + 48)
    }

    @ViewBuilder
    private func card(for wallpaper: Wallpaper, index: Int) -> some View {
        // The first card starts at the viewport center. A shared scroll
        // offset keeps depth calculations in one coordinate space, with
        // zIndex applied to the actual siblings in the lazy stack.
        let step = cardWidth + (reduceMotion ? Space.md : spacing)
        let raw = (CGFloat(index) * step + scrollOffset) / 320
        let clamped = reduceMotion ? 0 : max(-1.4, min(1.4, raw))
        let angle = clamped * maxAngle
        let scale = max(0.66, 1.0 - abs(clamped) * maxScaleLoss)
        let opacity = max(minOpacity, 1.0 - abs(clamped) * 0.55)
        let z = 1.0 - abs(clamped)

        CarouselCard(wallpaper: wallpaper, onApply: onTap)
            .frame(width: cardWidth, height: cardHeight)
            .scaleEffect(scale)
            .rotation3DEffect(
                .degrees(-angle),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.6
            )
            .opacity(opacity)
            .zIndex(z)
    }
}
