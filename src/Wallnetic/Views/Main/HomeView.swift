import SwiftUI

/// Netflix-style home with full-screen hero and horizontal carousels
struct HomeView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var heroIndex = 0
    @State private var heroTimer: Timer?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // Full-width hero - extends behind the top bar
                heroBanner
                    .padding(.top, -46) // Overlap into top bar area

                // Carousels below hero
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
        .background(Color.black)
        .onAppear { startHeroTimer() }
        .onDisappear { heroTimer?.invalidate() }
    }

    // MARK: - Netflix Hero Banner

    private var heroBanner: some View {
        let wallpapers = Array(wallpaperManager.wallpapers.prefix(5))
        let currentWallpaper = heroIndex < wallpapers.count ? wallpapers[heroIndex] : nil

        return VStack(spacing: 0) {
            // Image area
            ZStack {
                // Background image
                if let wp = currentWallpaper {
                    HeroBannerCard(wallpaper: wp)
                        .id(heroIndex)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.8), value: heroIndex)
                }

                // Gradient
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.3),
                        .init(color: .black, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
            .frame(height: 380)
            .clipped()

            // Info + Buttons area (below image, on black bg, always visible)
            if let wp = currentWallpaper {
                VStack(alignment: .leading, spacing: 12) {
                    // Title
                    Text(wp.name)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .truncationMode(.tail)

                    // Metadata
                    HStack(spacing: 12) {
                        Text(wp.formattedResolution)
                            .foregroundColor(.green)
                        Text(wp.formattedDuration)
                            .foregroundColor(.white.opacity(0.6))
                        Text(wp.formattedFileSize)
                            .foregroundColor(.white.opacity(0.6))

                        if wp.id == wallpaperManager.currentWallpaper?.id {
                            HStack(spacing: 4) {
                                Circle().fill(.green).frame(width: 6, height: 6)
                                Text("Active").foregroundColor(.green)
                            }
                        }
                    }
                    .font(.system(size: 12, weight: .medium))

                    // Buttons
                    HStack(spacing: 10) {
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
                            .background(Color.white)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
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
                            .background(Color.white.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
                            )
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        // Page indicators
                        HStack(spacing: 4) {
                            ForEach(0..<min(wallpapers.count, 5), id: \.self) { i in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(i == heroIndex ? Color.white : Color.white.opacity(0.3))
                                    .frame(width: i == heroIndex ? 18 : 12, height: 3)
                                    .animation(.easeInOut(duration: 0.3), value: heroIndex)
                            }
                        }
                    }
                }
                .padding(.horizontal, 48)
                .padding(.top, -40) // Overlap slightly into image area
                .padding(.bottom, 16)
            }
        }
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
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 48)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(wallpapers) { wallpaper in
                        CarouselCard(wallpaper: wallpaper)
                    }
                }
                .padding(.horizontal, 48)
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

    private let cardWidth: CGFloat = 240
    private let cardHeight: CGFloat = 135

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Thumbnail with hover overlay
            ZStack(alignment: .bottom) {
                // Image
                Group {
                    if let thumbnail = thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                            .overlay { ProgressView().scaleEffect(0.6) }
                    }
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipped()

                // Hover overlay
                if isHovering {
                    // Full dark overlay
                    Color.black.opacity(0.4)

                    // Play icon center
                    Image(systemName: "play.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.5), radius: 4)

                    // Bottom gradient + info
                    VStack {
                        Spacer()
                        LinearGradient(colors: [.clear, .black.opacity(0.9)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 55)
                    }

                    // Duration badge top-right
                    VStack {
                        HStack {
                            Spacer()
                            Text(wallpaper.formattedDuration)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(3)
                                .padding(6)
                        }
                        Spacer()
                    }
                }

                // Active indicator
                if wallpaper.id == wallpaperManager.currentWallpaper?.id {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white, lineWidth: 2)
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .cornerRadius(6)
            .shadow(color: .black.opacity(isHovering ? 0.5 : 0), radius: 12, y: 6)

            // Name below card - always visible, max 3 lines
            Text(wallpaper.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(3)
                .truncationMode(.tail)
                .frame(width: cardWidth, alignment: .leading)
        }
        .animation(.easeOut(duration: 0.2), value: isHovering)
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
            Divider()
            Button(role: .destructive) { wallpaperManager.removeWallpaper(wallpaper) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .task {
            thumbnail = await wallpaper.generateThumbnail(size: CGSize(width: 480, height: 270))
        }
    }
}
