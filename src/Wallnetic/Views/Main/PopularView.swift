import SwiftUI

/// Popular tab - sorted wallpapers with trending indicators
struct PopularView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager

    enum SortOption: String, CaseIterable {
        case newest = "Newest"
        case oldest = "Oldest"
        case nameAZ = "Name A-Z"
        case nameZA = "Name Z-A"
        case largest = "Largest"
        case longest = "Longest"
    }

    @State private var sortOption: SortOption = .newest

    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 16)
    ]

    var sortedWallpapers: [Wallpaper] {
        switch sortOption {
        case .newest: return wallpaperManager.wallpapers.sorted { $0.dateAdded > $1.dateAdded }
        case .oldest: return wallpaperManager.wallpapers.sorted { $0.dateAdded < $1.dateAdded }
        case .nameAZ: return wallpaperManager.wallpapers.sorted { $0.name < $1.name }
        case .nameZA: return wallpaperManager.wallpapers.sorted { $0.name > $1.name }
        case .largest: return wallpaperManager.wallpapers.sorted { $0.fileSize > $1.fileSize }
        case .longest: return wallpaperManager.wallpapers.sorted { ($0.duration ?? 0) > ($1.duration ?? 0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sort bar
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundColor(.orange)
                Text("Popular")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))

                Spacer()

                // Sort picker
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Picker("", selection: $sortOption) {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .frame(width: 100)
                }

                Text("\(sortedWallpapers.count) wallpapers")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            // Grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(sortedWallpapers.enumerated()), id: \.element.id) { index, wallpaper in
                        PopularCard(wallpaper: wallpaper, rank: index + 1)
                    }
                }
                .padding(20)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Popular Card

struct PopularCard: View {
    let wallpaper: Wallpaper
    let rank: Int
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var thumbnail: NSImage?
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
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

                // Rank badge
                Text("#\(rank)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(rank <= 3 ? Color.orange : Color.secondary.opacity(0.7))
                    )
                    .padding(8)

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

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(wallpaper.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(3)
                        .truncationMode(.tail)

                    Text("\(wallpaper.formattedResolution) \u{2022} \(wallpaper.formattedDuration)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if wallpaper.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.pink)
                }
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
        }
        .task { thumbnail = await wallpaper.generateThumbnail() }
    }
}
