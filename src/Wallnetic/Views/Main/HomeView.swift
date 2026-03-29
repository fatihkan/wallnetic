import SwiftUI

/// Netflix/Disney+ style home view with hero banner and carousels
struct HomeView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var heroIndex = 0
    @State private var heroTimer: Timer?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 28) {
                // Hero Banner
                if !wallpaperManager.wallpapers.isEmpty {
                    heroBanner
                        .padding(.horizontal, 20)
                }

                // Carousel sections
                if !favoritesWallpapers.isEmpty {
                    CarouselSection(
                        title: "My Favorites",
                        icon: "heart.fill",
                        iconColor: .pink,
                        wallpapers: favoritesWallpapers
                    )
                }

                if !recentWallpapers.isEmpty {
                    CarouselSection(
                        title: "Recently Added",
                        icon: "clock.fill",
                        iconColor: .blue,
                        wallpapers: recentWallpapers
                    )
                }

                CarouselSection(
                    title: "All Wallpapers",
                    icon: "photo.stack.fill",
                    iconColor: .purple,
                    wallpapers: wallpaperManager.wallpapers
                )

                Spacer(minLength: 40)
            }
            .padding(.top, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { startHeroTimer() }
        .onDisappear { heroTimer?.invalidate() }
    }

    // MARK: - Hero Banner

    private var heroBanner: some View {
        let wallpapers = Array(wallpaperManager.wallpapers.prefix(5))

        return ZStack(alignment: .bottomLeading) {
            // Background image
            if heroIndex < wallpapers.count {
                HeroBannerCard(wallpaper: wallpapers[heroIndex])
                    .id(heroIndex)
                    .transition(.opacity)
            }

            // Gradient overlay
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.2),
                    .init(color: Color(nsColor: .windowBackgroundColor).opacity(0.7), location: 0.7),
                    .init(color: Color(nsColor: .windowBackgroundColor), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Info overlay
            if heroIndex < wallpapers.count {
                let wallpaper = wallpapers[heroIndex]
                VStack(alignment: .leading, spacing: 10) {
                    Text(wallpaper.name)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack(spacing: 16) {
                        Label(wallpaper.formattedResolution, systemImage: "aspectratio")
                        Label(wallpaper.formattedDuration, systemImage: "clock")
                        Label(wallpaper.formattedFileSize, systemImage: "doc")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            wallpaperManager.setWallpaper(wallpaper)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 12))
                                Text("Set Wallpaper")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                                wallpaperManager.toggleFavorite(wallpaper)
                            }
                        } label: {
                            Image(systemName: wallpaper.isFavorite ? "heart.fill" : "heart")
                                .font(.system(size: 16))
                                .foregroundColor(wallpaper.isFavorite ? .pink : .secondary)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.secondary.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }

            // Page indicators
            HStack(spacing: 6) {
                Spacer()
                ForEach(0..<min(wallpapers.count, 5), id: \.self) { i in
                    Capsule()
                        .fill(i == heroIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: i == heroIndex ? 20 : 6, height: 6)
                        .animation(.easeInOut(duration: 0.2), value: heroIndex)
                }
            }
            .padding(.trailing, 28)
            .padding(.bottom, 24)
        }
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
        heroTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { _ in
            let count = min(wallpaperManager.wallpapers.count, 5)
            guard count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.6)) {
                heroIndex = (heroIndex + 1) % count
            }
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
                Rectangle()
                    .fill(
                        LinearGradient(colors: [.purple.opacity(0.2), .blue.opacity(0.15)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .overlay { ProgressView() }
            }
        }
        .task {
            thumbnail = await wallpaper.generateThumbnail(size: CGSize(width: 900, height: 500))
        }
    }
}

// MARK: - Carousel Section

struct CarouselSection: View {
    let title: String
    let icon: String
    let iconColor: Color
    let wallpapers: [Wallpaper]

    @EnvironmentObject var wallpaperManager: WallpaperManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(iconColor)

                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))

                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 28, height: 18)
                    .overlay(
                        Text("\(wallpapers.count)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    )

                Spacer()
            }
            .padding(.horizontal, 24)

            // Horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(wallpapers) { wallpaper in
                        CarouselCard(wallpaper: wallpaper)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

// MARK: - Carousel Card

struct CarouselCard: View {
    let wallpaper: Wallpaper
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var thumbnail: NSImage?
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                // Thumbnail
                Group {
                    if let thumbnail = thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.1))
                            .aspectRatio(16/9, contentMode: .fit)
                            .overlay { ProgressView().scaleEffect(0.7) }
                    }
                }
                .frame(width: 230, height: 130)
                .clipped()

                // Duration
                Text(wallpaper.formattedDuration)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.65))
                    .cornerRadius(4)
                    .padding(8)

                // Hover overlay
                if isHovering {
                    Color.black.opacity(0.35)

                    VStack(spacing: 6) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 38))
                            .foregroundColor(.white.opacity(0.9))

                        Text("Double-click to apply")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                // Active border
                if wallpaper.id == wallpaperManager.currentWallpaper?.id {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.accentColor, lineWidth: 2.5)
                }
            }
            .cornerRadius(10)
            .scaleEffect(isHovering ? 1.03 : 1.0)
            .shadow(color: .black.opacity(isHovering ? 0.25 : 0.05), radius: isHovering ? 12 : 4, y: isHovering ? 6 : 2)
            .animation(.easeOut(duration: 0.2), value: isHovering)

            // Info
            HStack {
                Text(wallpaper.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Spacer()

                if wallpaper.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.pink)
                }
            }
            .frame(width: 230)
        }
        .onHover { h in isHovering = h }
        .onTapGesture(count: 2) {
            wallpaperManager.setWallpaper(wallpaper)
        }
        .contextMenu {
            Button { wallpaperManager.setWallpaper(wallpaper) } label: {
                Label("Set as Wallpaper", systemImage: "photo.on.rectangle")
            }
            Button {
                withAnimation { wallpaperManager.toggleFavorite(wallpaper) }
            } label: {
                Label(wallpaper.isFavorite ? "Remove Favorite" : "Add Favorite",
                      systemImage: wallpaper.isFavorite ? "heart.fill" : "heart")
            }
            Divider()
            Button(role: .destructive) { wallpaperManager.removeWallpaper(wallpaper) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .task {
            thumbnail = await wallpaper.generateThumbnail(size: CGSize(width: 460, height: 260))
        }
    }
}
