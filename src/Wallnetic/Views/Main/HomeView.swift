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
    @State private var selectedHeroID: UUID?
    @State private var isHeroHovered = false
    @State private var isAutoAdvancing = true
    @State private var heroScrollY: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var featuredWallpapers: [Wallpaper] {
        Array(wallpaperManager.wallpapers.prefix(5))
    }

    private var selectedHero: Wallpaper? {
        WallpaperBrowsing.selected(in: featuredWallpapers, currentID: selectedHeroID)
    }

    private var shouldAutoAdvance: Bool {
        isAutoAdvancing && !reduceMotion && !isHeroHovered && scenePhase == .active && featuredWallpapers.count > 1
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                heroBanner
                    .onHover { isHeroHovered = $0 }
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
        .task(id: shouldAutoAdvance) {
            guard shouldAutoAdvance else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 7_000_000_000) }
                catch { return }
                guard !Task.isCancelled else { return }
                advanceHero(backwards: false)
            }
        }
        .modifier(KeyPressModifier(
            onSpace: {
                if let wp = selectedHero {
                    isAutoAdvancing = false
                    wallpaperManager.setWallpaper(wp)
                }
            },
            onLeft: { heroPrev() },
            onRight: { heroNext() }
        ))
    }

    // MARK: - Cinematic Hero Banner

    private var heroBanner: some View {
        let wallpapers = featuredWallpapers
        let currentWallpaper = selectedHero

        // Scroll-driven parallax: scale up + push down as user scrolls
        let parallax = reduceMotion ? 0 : max(-200, min(200, heroScrollY))
        let scale = 1.0 + max(0, parallax) * 0.0008
        let yOffset = parallax * 0.45

        return VStack(spacing: 0) {
            ZStack {
                if let wp = currentWallpaper {
                    HeroBannerCard(wallpaper: wp)
                        .id(wp.id)
                        .scaleEffect(scale)
                        .offset(y: yOffset * 0.3)
                        .transition(.opacity)
                        .animation(reduceMotion ? nil : .easeInOut(duration: Anim.hero), value: wp.id)
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

            // Info section
            if let wp = currentWallpaper {
                heroInfo(wp, wallpapers: wallpapers)
            }
        }
    }

    @ViewBuilder
    private func heroInfo(_ wp: Wallpaper, wallpapers: [Wallpaper]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(wp.displayName)
                .font(Typo.display)
                .tracking(Typo.displayTracking)
                .foregroundColor(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .shadow(color: Surface.vignetteEdge.opacity(1.6), radius: 8, y: 2)

            // Metadata pills
            HStack(spacing: 8) {
                metadataPill(wp.formattedResolution, color: .primary.opacity(0.7))
                metadataPill(wp.formattedDuration, color: .primary.opacity(0.7))
                metadataPill(wp.formattedFileSize, color: .primary.opacity(0.7))

                if wp.id == wallpaperManager.currentWallpaper?.id {
                    HStack(spacing: 4) {
                        Image(systemName: wallpaperManager.isPlaying ? "play.fill" : "pause.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text(wallpaperManager.isPlaying ? "Playing" : "Paused")
                    }
                    .foregroundStyle(.primary)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Surface.glassControl))
                }
            }

            // Action buttons
            HStack(spacing: Space.xs + 2) {
                Button {
                    isAutoAdvancing = false
                    wallpaperManager.setWallpaper(wp)
                } label: {
                    Label("Set wallpaper", systemImage: "play.fill")
                        .font(Typo.button)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                WallneticButton.ghost(
                    wp.isFavorite ? "In My List" : "Add to My List",
                    icon: wp.isFavorite ? "checkmark" : "plus"
                ) {
                    withAnimation(.spring(response: Anim.medium, dampingFraction: 0.5)) {
                        wallpaperManager.toggleFavorite(wp)
                    }
                }

                Spacer()

                if wallpapers.count > 1 {
                    HStack(spacing: Space.xxs) {
                        Button(action: heroPrev) {
                            Image(systemName: "chevron.left").frame(width: 28, height: 28)
                        }
                        .help("Previous featured wallpaper")
                        .accessibilityLabel("Previous featured wallpaper")

                        ForEach(Array(wallpapers.enumerated()), id: \.element.id) { index, wallpaper in
                            Button {
                                isAutoAdvancing = false
                                withAnimation(reduceMotion ? nil : Anim.transition) { selectedHeroID = wallpaper.id }
                            } label: {
                                Capsule()
                                    .fill(wallpaper.id == wp.id ? Color.accentColor : Color.primary.opacity(0.25))
                                    .frame(width: wallpaper.id == wp.id ? 20 : 8, height: 4)
                                    .frame(width: 24, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Featured wallpaper \(index + 1): \(wallpaper.displayName)")
                            .accessibilityAddTraits(wallpaper.id == wp.id ? [.isSelected] : [])
                        }

                        Button(action: heroNext) {
                            Image(systemName: "chevron.right").frame(width: 28, height: 28)
                        }
                        .help("Next featured wallpaper")
                        .accessibilityLabel("Next featured wallpaper")

                        if !reduceMotion {
                            Button { isAutoAdvancing.toggle() } label: {
                                Image(systemName: isAutoAdvancing ? "pause.fill" : "play.fill")
                                    .frame(width: 28, height: 28)
                            }
                            .help(isAutoAdvancing ? "Pause slideshow" : "Resume slideshow")
                            .accessibilityLabel(isAutoAdvancing ? "Pause slideshow" : "Resume slideshow")
                        }
                    }
                    .buttonStyle(.plain)
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

    private func advanceHero(backwards: Bool) {
        let next = WallpaperBrowsing.adjacent(in: featuredWallpapers, currentID: selectedHero?.id, backwards: backwards)
        withAnimation(reduceMotion ? nil : Anim.transition) { selectedHeroID = next?.id }
    }

    private func heroNext() {
        isAutoAdvancing = false
        advanceHero(backwards: false)
    }

    private func heroPrev() {
        isAutoAdvancing = false
        advanceHero(backwards: true)
    }
}

// MARK: - Hero Banner Card

struct HeroBannerCard: View {
    let wallpaper: Wallpaper
    @State private var thumbnail: NSImage?
    @State private var startDate: Date = Date()
    @State private var isWindowVisible: Bool = true
    @State private var isLoadingThumbnail = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // Stop decorative frame updates while inactive or when Reduce Motion
        // is enabled. Scene activity does not imply per-window visibility.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isWindowVisible || reduceMotion || scenePhase != .active)) { ctx in
            let elapsed = ctx.date.timeIntervalSince(startDate)
            let cycle: Double = 14
            let raw = (elapsed.truncatingRemainder(dividingBy: cycle)) / cycle
            let phase = raw < 0.5 ? raw * 2 : (1 - raw) * 2

            Group {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .scaleEffect(reduceMotion ? 1 : 1.06 + phase * 0.06)
                        .offset(
                            x: reduceMotion ? 0 : (phase - 0.5) * 36,
                            y: reduceMotion ? 0 : (phase - 0.5) * 22
                        )
                } else {
                    Surface.deepFade
                        .overlay {
                            if isLoadingThumbnail {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Preview unavailable", systemImage: "film")
                                    .font(Typo.body)
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
            }
        }
        .task(id: wallpaper.id) {
            thumbnail = nil
            isLoadingThumbnail = true
            let image = await wallpaper.generateThumbnail(size: CGSize(width: 1280, height: 720))
            guard !Task.isCancelled else { return }
            thumbnail = image
            isLoadingThumbnail = false
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
    var onApply: ((Wallpaper) -> Void)? = nil
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var thumbnail: NSImage?
    @State private var isLoadingThumbnail = true
    @State private var isHovering = false
    @State private var renamingWallpaper: Wallpaper?
    @State private var renameText = ""
    @State private var pointer = CGPoint(x: 0.5, y: 0.5)
    @State private var lastPointerWrite: TimeInterval = 0
    private static let pointerThrottle: TimeInterval = 1.0 / 30.0  // P1-7

    private let cardWidth: CGFloat = 240
    private let cardHeight: CGFloat = 135

    /// Subtle magnetic tilt: pointer's offset from center drives a ±6°
    /// rotation around the y/x axes plus a 2-3px translation. Falls back
    /// to flat when not hovering.
    private var tiltX: Double {
        guard isHovering && !reduceMotion else { return 0 }
        return Double(0.5 - pointer.y) * 8  // top → tilt forward
    }

    private var tiltY: Double {
        guard isHovering && !reduceMotion else { return 0 }
        return Double(pointer.x - 0.5) * 8  // right → tilt right
    }

    private var glareOffset: CGFloat {
        min(1, max(0, pointer.x))
    }

    /// Specular intensity scales with tilt magnitude — like a real lens
    /// reflecting more light when angled.
    private var specularIntensity: Double {
        guard isHovering && !reduceMotion else { return 0 }
        let mag = sqrt(tiltX * tiltX + tiltY * tiltY)
        return min(0.22, 0.06 + mag / 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if let onApply { onApply(wallpaper) }
                else { wallpaperManager.setWallpaper(wallpaper) }
            } label: {
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
                                .overlay {
                                    if isLoadingThumbnail {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: "film").foregroundStyle(.secondary)
                                    }
                                }
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
                .scaleEffect(isHovering && !reduceMotion ? 1.04 : 1.0)
                .background(
                    // Trackpad/mouse position tracker (overlay placed in front of the card for hit testing)
                    GeometryReader { proxy in
                        Color.clear.contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let loc):
                                    guard !reduceMotion, proxy.size.width > 0, proxy.size.height > 0 else { return }
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
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Set \(wallpaper.displayName) as wallpaper")
            .accessibilityAddTraits(wallpaper.id == wallpaperManager.currentWallpaper?.id ? [.isSelected] : [])
            .help("Set as wallpaper")

            Text(wallpaper.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary.opacity(isHovering ? 0.95 : 0.75))
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(width: cardWidth, alignment: .leading)
        }
        .animation(reduceMotion ? nil : .spring(response: Anim.enter, dampingFraction: 0.75), value: isHovering)
        .onHover { h in isHovering = h }
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
        .task(id: wallpaper.id) {
            thumbnail = nil
            isLoadingThumbnail = true
            let image = await wallpaper.generateThumbnail(size: CGSize(width: 480, height: 270))
            guard !Task.isCancelled else { return }
            thumbnail = image
            isLoadingThumbnail = false
        }
    }
}
