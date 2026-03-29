import SwiftUI

/// Explore tab with search, filter and grid view
struct ExploreView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    let searchText: String

    @State private var selectedCategory: String = "All"

    private let categories = ["All", "Favorites", "Recent", "Long", "Short", "HD", "4K"]

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 14)
    ]

    var filteredWallpapers: [Wallpaper] {
        var result = wallpaperManager.wallpapers

        // Category filter
        switch selectedCategory {
        case "Favorites":
            result = result.filter { $0.isFavorite }
        case "Recent":
            let week = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            result = result.filter { $0.dateAdded > week }
        case "Long":
            result = result.filter { ($0.duration ?? 0) > 10 }
        case "Short":
            result = result.filter { ($0.duration ?? 0) <= 10 }
        case "HD":
            result = result.filter { ($0.resolution?.width ?? 0) >= 1920 && ($0.resolution?.width ?? 0) < 3840 }
        case "4K":
            result = result.filter { ($0.resolution?.width ?? 0) >= 3840 }
        default:
            break
        }

        // Search filter
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Category filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { category in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedCategory = category
                            }
                        } label: {
                            Text(category)
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(selectedCategory == category
                                              ? Color.accentColor
                                              : Color.secondary.opacity(0.15))
                                )
                                .foregroundColor(selectedCategory == category ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            Divider()

            // Results count
            HStack {
                Text("\(filteredWallpapers.count) wallpapers")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            // Grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(filteredWallpapers) { wallpaper in
                        ExploreCard(wallpaper: wallpaper)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Explore Card

struct ExploreCard: View {
    let wallpaper: Wallpaper
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var thumbnail: NSImage?
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .aspectRatio(16/9, contentMode: .fit)
                        .overlay { ProgressView() }
                }

                // Badges
                VStack {
                    HStack {
                        if wallpaper.isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Circle().fill(.pink.opacity(0.8)))
                                .padding(6)
                        }
                        Spacer()
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        Text(wallpaper.formattedDuration)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.6))
                            .cornerRadius(4)
                            .padding(6)
                    }
                }

                if isHovering {
                    Color.black.opacity(0.3)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .cornerRadius(10)
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .shadow(color: .black.opacity(isHovering ? 0.15 : 0), radius: 6, y: 3)
            .onTapGesture(count: 2) {
                wallpaperManager.setWallpaper(wallpaper)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(wallpaper.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Text("\(wallpaper.formattedResolution) \u{2022} \(wallpaper.formattedFileSize)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { isHovering = h } }
        .contextMenu {
            Button { wallpaperManager.setWallpaper(wallpaper) } label: {
                Label("Set as Wallpaper", systemImage: "photo.on.rectangle")
            }
            Button { wallpaperManager.toggleFavorite(wallpaper) } label: {
                Label(wallpaper.isFavorite ? "Remove Favorite" : "Add Favorite",
                      systemImage: wallpaper.isFavorite ? "heart.fill" : "heart")
            }
            Divider()
            Button(role: .destructive) { wallpaperManager.removeWallpaper(wallpaper) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .task { thumbnail = await wallpaper.generateThumbnail() }
    }
}
