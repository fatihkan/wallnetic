import SwiftUI

/// Netflix/Disney+ style home view with hero banner and carousels
struct HomeView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var heroIndex = 0
    @State private var heroTimer: Timer?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                // Hero Banner
                if !wallpaperManager.wallpapers.isEmpty {
                    heroBanner
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
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear { startHeroTimer() }
        .onDisappear { heroTimer?.invalidate() }
    }

    // MARK: - Hero Banner

    private var heroBanner: some View {
        let wallpapers = Array(wallpaperManager.wallpapers.prefix(5))

        return ZStack(alignment: .bottomLeading) {
            // Background image
            TabView(selection: $heroIndex) {
                ForEach(Array(wallpapers.enumerated()), id: \.element.id) { index, wallpaper in
                    HeroBannerCard(wallpaper: wallpaper)
                        .tag(index)
                }
            }
            .tabViewStyle(.automatic)
            .frame(height: 320)

            // Gradient overlay
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.3),
                    .init(color: Color(nsColor: .controlBackgroundColor).opacity(0.8), location: 0.8),
                    .init(color: Color(nsColor: .controlBackgroundColor), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Info overlay
            if heroIndex < wallpapers.count {
                let wallpaper = wallpapers[heroIndex]
                VStack(alignment: .leading, spacing: 8) {
                    Text(wallpaper.name)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    HStack(spacing: 12) {
                        Label(wallpaper.formattedResolution, systemImage: "aspectratio")
                        Label(wallpaper.formattedDuration, systemImage: "clock")
                        Label(wallpaper.formattedFileSize, systemImage: "doc")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            wallpaperManager.setWallpaper(wallpaper)
                        } label: {
                            Label("Set Wallpaper", systemImage: "play.fill")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button {
                            wallpaperManager.toggleFavorite(wallpaper)
                        } label: {
                            Image(systemName: wallpaper.isFavorite ? "heart.fill" : "heart")
                                .font(.title3)
                                .foregroundColor(wallpaper.isFavorite ? .pink : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }

            // Page dots
            HStack(spacing: 6) {
                Spacer()
                ForEach(0..<wallpapers.count, id: \.self) { i in
                    Circle()
                        .fill(i == heroIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.trailing, 24)
            .padding(.bottom, 20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
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
        heroTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            let count = min(wallpaperManager.wallpapers.count, 5)
            guard count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
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
        ZStack {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [.purple.opacity(0.3), .blue.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .task {
            thumbnail = await wallpaper.generateThumbnail(size: CGSize(width: 800, height: 450))
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
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("\(wallpapers.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.secondary.opacity(0.15)))
            }
            .padding(.horizontal, 24)

            // Horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(wallpapers) { wallpaper in
                        CarouselCard(wallpaper: wallpaper)
                            .onTapGesture(count: 2) {
                                wallpaperManager.setWallpaper(wallpaper)
                            }
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
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                        .frame(width: 220, height: 124)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 220, height: 124)
                        .overlay { ProgressView() }
                }

                // Duration badge
                Text(wallpaper.formattedDuration)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.6))
                    .cornerRadius(4)
                    .padding(6)

                // Hover play overlay
                if isHovering {
                    Color.black.opacity(0.3)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.white.opacity(0.9))
                }

                // Active indicator
                if wallpaper.id == wallpaperManager.currentWallpaper?.id {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
            .cornerRadius(8)
            .scaleEffect(isHovering ? 1.03 : 1.0)
            .shadow(color: .black.opacity(isHovering ? 0.2 : 0), radius: 6, y: 3)

            // Name
            Text(wallpaper.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(width: 220, alignment: .leading)
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .task {
            thumbnail = await wallpaper.generateThumbnail(size: CGSize(width: 440, height: 248))
        }
    }
}
