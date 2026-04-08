import SwiftUI

/// Striking home with cinematic hero and glass carousel cards
struct HomeView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var heroIndex = 0
    @State private var heroTimer: Timer?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                heroBanner
                    .padding(.top, -46)

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
        .background(Color.clear)
        .onAppear { startHeroTimer() }
        .onDisappear { heroTimer?.invalidate() }
    }

    // MARK: - Cinematic Hero Banner

    private var heroBanner: some View {
        let wallpapers = Array(wallpaperManager.wallpapers.prefix(5))
        let currentWallpaper = heroIndex < wallpapers.count ? wallpapers[heroIndex] : nil

        return VStack(spacing: 0) {
            ZStack {
                if let wp = currentWallpaper {
                    HeroBannerCard(wallpaper: wp)
                        .id(heroIndex)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: Anim.hero), value: heroIndex)
                }

                // Cinematic gradient overlay
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.2),
                        .init(color: Color(red: 0.02, green: 0.02, blue: 0.06).opacity(0.5), location: 0.5),
                        .init(color: Color(red: 0.02, green: 0.02, blue: 0.06), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                // Side vignette
                HStack {
                    LinearGradient(
                        colors: [Color.black.opacity(0.4), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: 120)
                    Spacer()
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.4)],
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
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(2)
                .truncationMode(.tail)
                .shadow(color: .black.opacity(0.5), radius: 8)

            // Metadata pills
            HStack(spacing: 8) {
                metadataPill(wp.formattedResolution, color: .green)
                metadataPill(wp.formattedDuration, color: .white.opacity(0.6))
                metadataPill(wp.formattedFileSize, color: .white.opacity(0.6))

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
            HStack(spacing: 10) {
                // Play button with glow
                Button {
                    wallpaperManager.setWallpaper(wp)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text("Use")
                            .fontWeight(.bold)
                    }
                    .font(.system(size: 14))
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(Color.white)
                    )
                }
                .buttonStyle(.plain)

                // My List button
                Button {
                    withAnimation(.spring(response: Anim.medium, dampingFraction: 0.5)) {
                        wallpaperManager.toggleFavorite(wp)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: wp.isFavorite ? "checkmark" : "plus")
                        Text("My List")
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                // Page indicators with glow
                HStack(spacing: 5) {
                    ForEach(0..<min(wallpapers.count, 5), id: \.self) { i in
                        Capsule()
                            .fill(i == heroIndex ? Color.accentColor : Color.white.opacity(0.2))
                            .frame(width: i == heroIndex ? 22 : 10, height: 3)
                            .neonGlow(.accentColor, isActive: i == heroIndex, radius: 4)
                            .animation(.spring(response: Anim.medium, dampingFraction: 0.7), value: heroIndex)
                    }
                }
            }
        }
        .padding(.horizontal, 48)
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
}

// MARK: - Hero Banner Card

struct HeroBannerCard: View {
    let wallpaper: Wallpaper
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.black
            }
        }
        .task {
            thumbnail = await wallpaper.generateThumbnail(size: CGSize(width: 1280, height: 720))
        }
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
                    .foregroundColor(.white)

                Text("\(wallpapers.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 48)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(Array(wallpapers.enumerated()), id: \.element.id) { index, wallpaper in
                        CarouselCard(wallpaper: wallpaper)
                            .staggered(index: index)
                    }
                }
                .padding(.horizontal, 48)
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

    private let cardWidth: CGFloat = 240
    private let cardHeight: CGFloat = 135

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
                            .fill(Color.white.opacity(0.03))
                            .overlay { ProgressView().scaleEffect(0.6) }
                    }
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipped()

                // Hover overlay
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

                // Duration badge
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
            .glowCard(isHovering: isHovering, cornerRadius: 8)
            .scaleEffect(isHovering ? 1.03 : 1.0)

            Text(wallpaper.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(isHovering ? 0.95 : 0.7))
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
            Button { wallpaperManager.setWallpaper(wallpaper) } label: {
                Label("Set as Wallpaper", systemImage: "play.fill")
            }
            Button {
                withAnimation { wallpaperManager.toggleFavorite(wallpaper) }
            } label: {
                Label(wallpaper.isFavorite ? "Remove from My List" : "Add to My List",
                      systemImage: wallpaper.isFavorite ? "checkmark" : "plus")
            }
            Button {
                renameText = wallpaper.displayName
                renamingWallpaper = wallpaper
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) { wallpaperManager.removeWallpaper(wallpaper) } label: {
                Label("Delete", systemImage: "trash")
            }
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
