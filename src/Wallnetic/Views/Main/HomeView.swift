import SwiftUI

private struct HeroScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// DUSUK-2: scoped to HomeView so it can't accidentally be reused as
// app-wide. Access via `HomeView.horizontalInset`.
extension HomeView {
    static let horizontalInset: CGFloat = 48
}
private var homeHorizontalInset: CGFloat { HomeView.horizontalInset }

/// Striking home with cinematic hero and glass carousel cards
struct HomeView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var heroIndex = 0
    @State private var heroTimer: Timer?
    @State private var heroScrollY: CGFloat = 0

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                heroBanner
                    .padding(.top, -46)
                    // P0-2: replaces the recursive DispatchQueue.async +
                    // @State write antipattern. PreferenceKey reports
                    // upward once per actual layout pass; no body
                    // invalidation loop.
                    .background(GeometryReader { geo in
                        Color.clear.preference(
                            key: HeroScrollOffsetKey.self,
                            value: geo.frame(in: .named("homeScroll")).minY
                        )
                    })

                VStack(spacing: 28) {
                    if !favoritesWallpapers.isEmpty {
                        CarouselSection(
                            title: "My List",
                            icon: "heart.fill",
                            iconColor: .pink,
                            wallpapers: favoritesWallpapers
                        )
                    }

                    if !recentWallpapers.isEmpty {
                        CarouselSection(
                            title: "Recently Added",
                            icon: "sparkles",
                            iconColor: .yellow,
                            wallpapers: recentWallpapers
                        )
                    }

                    if wallpaperManager.wallpapers.count > 3 {
                        CarouselSection(
                            title: "All Wallpapers",
                            icon: "square.grid.2x2.fill",
                            iconColor: .blue,
                            wallpapers: wallpaperManager.wallpapers
                        )
                    }

                    Spacer(minLength: 60)
                }
                .padding(.top, 20)
            }
        }
        .coordinateSpace(name: "homeScroll")
        .onPreferenceChange(HeroScrollOffsetKey.self) { value in
            // Coalesced: only ever a single write per layout pass.
            heroScrollY = value
        }
        .background(Color.clear)
        .onAppear { startHeroTimer() }
        .onDisappear { heroTimer?.invalidate() }
        .modifier(KeyPressModifier(
            onSpace: {
                if let wp = wallpaperManager.wallpapers[safe: heroIndex] {
                    wallpaperManager.setWallpaper(wp)
                }
            },
            onLeft: { heroPrev() },
            onRight: { heroNext() }
        ))
    }

    // MARK: - Cinematic Hero Banner

    private var heroBanner: some View {
        let wallpapers = Array(wallpaperManager.wallpapers.prefix(5))
        let currentWallpaper = heroIndex < wallpapers.count ? wallpapers[heroIndex] : nil

        // Scroll-driven parallax: scale up + push down as user scrolls
        let parallax = max(-200, min(200, heroScrollY))
        let scale = 1.0 + max(0, parallax) * 0.0008
        let yOffset = parallax * 0.45

        return VStack(spacing: 0) {
            ZStack {
                if let wp = currentWallpaper {
                    HeroBannerCard(wallpaper: wp)
                        .id(heroIndex)
                        .scaleEffect(scale)
                        .offset(y: yOffset * 0.3)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: Anim.hero), value: heroIndex)
                }

                // Cinematic gradient overlay (fades hero into window backdrop)
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.2),
                        .init(color: Surface.deepFade.opacity(0.5), location: 0.5),
                        .init(color: Surface.deepFade, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                // Side vignette
                HStack {
                    LinearGradient(
                        colors: [Surface.vignetteEdge.opacity(1.2), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: 120)
                    Spacer()
                    LinearGradient(
                        colors: [.clear, Surface.vignetteEdge.opacity(1.2)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: 120)
                }
                .allowsHitTesting(false)
            }
            .frame(height: 400)
            .clipped()
            .shimmer()

            // Info section
            if let wp = currentWallpaper {
                heroInfo(wp, wallpapers: wallpapers)
            }
        }
    }

    @ViewBuilder
    private func heroInfo(_ wp: Wallpaper, wallpapers: [Wallpaper]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(wp.name)
                .font(Typo.display)
                .tracking(Typo.displayTracking)
                .foregroundColor(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .shadow(color: Surface.vignetteEdge.opacity(1.6), radius: 8, y: 2)

            // Metadata pills
            HStack(spacing: 8) {
                metadataPill(wp.formattedResolution, color: .green)
                metadataPill(wp.formattedDuration, color: .primary.opacity(0.7))
                metadataPill(wp.formattedFileSize, color: .primary.opacity(0.7))

                if wp.id == wallpaperManager.currentWallpaper?.id {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                            .neonGlow(.green, isActive: true, radius: 4)
                        Text("Active")
                            .foregroundColor(.green)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
                }
            }

            // Action buttons
            HStack(spacing: Space.xs + 2) {
                WallneticButton.primary("Use", icon: "play.fill", accent: .white) {
                    wallpaperManager.setWallpaper(wp)
                }

                WallneticButton.ghost(
                    "My List",
                    icon: wp.isFavorite ? "checkmark" : "plus"
                ) {
                    withAnimation(.spring(response: Anim.medium, dampingFraction: 0.5)) {
                        wallpaperManager.toggleFavorite(wp)
                    }
                }

                Spacer()

                // Page indicators with glow
                HStack(spacing: 5) {
                    ForEach(0..<min(wallpapers.count, 5), id: \.self) { i in
                        Capsule()
                            .fill(i == heroIndex ? Color.accentColor : Color.primary.opacity(0.25))
                            .frame(width: i == heroIndex ? 22 : 10, height: 3)
                            .neonGlow(.accentColor, isActive: i == heroIndex, radius: 4)
                            .animation(.spring(response: Anim.medium, dampingFraction: 0.7), value: heroIndex)
                    }
                }
            }
        }
        .padding(.horizontal, homeHorizontalInset)
        .padding(.top, -40)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func metadataPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(color)
    }

    // MARK: - Data

    private var favoritesWallpapers: [Wallpaper] {
        wallpaperManager.wallpapers.filter { $0.isFavorite }
    }

    private var recentWallpapers: [Wallpaper] {
        let oneWeek = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return wallpaperManager.wallpapers
            .filter { $0.dateAdded > oneWeek }
            .sorted { $0.dateAdded > $1.dateAdded }
    }

    private func startHeroTimer() {
        heroTimer = Timer.scheduledTimer(withTimeInterval: 7, repeats: true) { _ in
            let count = min(wallpaperManager.wallpapers.count, 5)
            guard count > 1 else { return }
            withAnimation { heroIndex = (heroIndex + 1) % count }
        }
    }

    private func heroNext() {
        let count = min(wallpaperManager.wallpapers.count, 5)
        guard count > 1 else { return }
        withAnimation { heroIndex = (heroIndex + 1) % count }
    }

    private func heroPrev() {
        let count = min(wallpaperManager.wallpapers.count, 5)
        guard count > 1 else { return }
        withAnimation { heroIndex = (heroIndex - 1 + count) % count }
    }
}

// MARK: - Hero Banner Card

struct HeroBannerCard: View {
    let wallpaper: Wallpaper
    @State private var thumbnail: NSImage?
    @State private var startDate: Date = Date()
    @State private var isWindowVisible: Bool = true

    var body: some View {
        // P2-10 + ORTA-1: phase derived from elapsed-since-appear rather
        // than absolute wall-clock — Mac sleep/wake doesn't cause the
        // Ken Burns to teleport mid-cycle.
        // ORTA-2: TimelineView paused when window is occluded so we
        // don't tick the hero off-screen.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isWindowVisible)) { ctx in
            let elapsed = ctx.date.timeIntervalSince(startDate)
            let cycle: Double = 14
            let raw = (elapsed.truncatingRemainder(dividingBy: cycle)) / cycle
            let phase = raw < 0.5 ? raw * 2 : (1 - raw) * 2

            Group {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .scaleEffect(1.06 + phase * 0.06)
                        .offset(
                            x: (phase - 0.5) * 36,
                            y: (phase - 0.5) * 22
                        )
                } else {
                    Surface.deepFade
                }
            }
        }
        .task {
            thumbnail = await wallpaper.generateThumbnail(size: CGSize(width: 1280, height: 720))
        }
        .onAppear {
            startDate = Date()
            isWindowVisible = true
        }
        .onDisappear { isWindowVisible = false }
    }
}

// MARK: - Carousel Section

struct CarouselSection: View {
    let title: String
    let icon: String
    let iconColor: Color
    let wallpapers: [Wallpaper]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(iconColor)
                    .neonGlow(iconColor, isActive: true, radius: 4)

                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)

                Text("\(wallpapers.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.4))
            }
            .padding(.horizontal, homeHorizontalInset)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(Array(wallpapers.enumerated()), id: \.element.id) { index, wallpaper in
                        CarouselCard(wallpaper: wallpaper)
                            .staggered(index: index)
                    }
                }
                .padding(.horizontal, homeHorizontalInset)
                .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - Carousel Card with Glow

struct CarouselCard: View {
    let wallpaper: Wallpaper
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var thumbnail: NSImage?
    @State private var isHovering = false
    @State private var renamingWallpaper: Wallpaper?
    @State private var renameText = ""
    @State private var pointer: CGPoint = .zero  // 0..1 within card
    @State private var lastPointerWrite: TimeInterval = 0
    private static let pointerThrottle: TimeInterval = 1.0 / 30.0  // P1-7

    private let cardWidth: CGFloat = 240
    private let cardHeight: CGFloat = 135

    /// Subtle magnetic tilt: pointer's offset from center drives a ±6°
    /// rotation around the y/x axes plus a 2-3px translation. Falls back
    /// to flat when not hovering.
    private var tiltX: Double {
        guard isHovering else { return 0 }
        return Double(0.5 - pointer.y) * 8  // top → tilt forward
    }

    private var tiltY: Double {
        guard isHovering else { return 0 }
        return Double(pointer.x - 0.5) * 8  // right → tilt right
    }

    private var glareOffset: CGFloat {
        guard isHovering else { return -1 }
        return pointer.x  // 0..1 follows pointer
    }

    /// Specular intensity scales with tilt magnitude — like a real lens
    /// reflecting more light when angled.
    private var specularIntensity: Double {
        guard isHovering else { return 0 }
        let mag = sqrt(tiltX * tiltX + tiltY * tiltY)
        return min(0.22, 0.06 + mag / 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                // Thumbnail
                Group {
                    if let thumbnail = thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(Surface.glassControl)
                            .overlay { ProgressView().scaleEffect(0.6) }
                    }
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipped()

                // Hover overlay — image content always dark, so keep
                // contrast overlay dark (not theme-aware) for legibility
                // of the play icon over thumbnails.
                if isHovering {
                    Color.black.opacity(0.35)

                    Image(systemName: "play.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.95))
                        .neonGlow(.white, isActive: true, radius: 8)

                    VStack {
                        Spacer()
                        LinearGradient(colors: [.clear, .black.opacity(0.8)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 50)
                    }
                }

                // Duration badge — over thumbnail image, stays dark for contrast
                VStack {
                    HStack {
                        Spacer()
                        Text(wallpaper.formattedDuration)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.black.opacity(0.6))
                            )
                            .padding(6)
                    }
                    Spacer()
                }

                // Active indicator
                if wallpaper.id == wallpaperManager.currentWallpaper?.id {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .neonGlow(.accentColor, isActive: true, radius: 6)
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .overlay(
                // Specular highlight — follows pointer, intensifies with
                // tilt magnitude. The gradient angle subtly tracks the
                // y-axis rotation so it looks like a real light source
                // staying overhead as the card tilts.
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0), location: max(0, glareOffset - 0.28)),
                        .init(color: .white.opacity(specularIntensity), location: glareOffset),
                        .init(color: .white.opacity(0), location: min(1, glareOffset + 0.28))
                    ],
                    startPoint: UnitPoint(x: 0.5 - tiltY / 50, y: 0),
                    endPoint: UnitPoint(x: 0.5 + tiltY / 50, y: 1)
                )
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            )
            .glowCard(isHovering: isHovering, cornerRadius: 8)
            .rotation3DEffect(.degrees(tiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.7)
            .rotation3DEffect(.degrees(tiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
            .scaleEffect(isHovering ? 1.04 : 1.0)
            .background(
                // Trackpad/mouse position tracker (overlay placed in front of the card for hit testing)
                GeometryReader { proxy in
                    Color.clear.contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let loc):
                                let now = CACurrentMediaTime()
                                guard now - lastPointerWrite >= Self.pointerThrottle else { return }
                                lastPointerWrite = now
                                pointer = CGPoint(
                                    x: min(max(loc.x / proxy.size.width, 0), 1),
                                    y: min(max(loc.y / proxy.size.height, 0), 1)
                                )
                            case .ended:
                                pointer = CGPoint(x: 0.5, y: 0.5)
                            }
                        }
                }
            )

            Text(wallpaper.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary.opacity(isHovering ? 0.95 : 0.75))
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(width: cardWidth, alignment: .leading)
        }
        .animation(.spring(response: Anim.enter, dampingFraction: 0.75), value: isHovering)
        .onHover { h in isHovering = h }
        .onTapGesture(count: 2) {
            wallpaperManager.setWallpaper(wallpaper)
        }
        .contextMenu {
            WallpaperContextMenu(wallpaper: wallpaper, onRename: {
                renameText = wallpaper.displayName
                renamingWallpaper = wallpaper
            })
        }
        .sheet(item: $renamingWallpaper) { wp in
            RenameWallpaperSheet(wallpaper: wp, title: $renameText, onSave: { newTitle in
                wallpaperManager.renameWallpaper(wp, to: newTitle)
                renamingWallpaper = nil
            }, onCancel: { renamingWallpaper = nil })
        }
        .task {
            thumbnail = await wallpaper.generateThumbnail(size: CGSize(width: 480, height: 270))
        }
    }
}
