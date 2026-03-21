import SwiftUI
import WidgetKit

/// Large widget showing current wallpaper, favorites grid, and controls
struct LargeWidgetView: View {
    let entry: WallpaperEntry

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(spacing: 12) {
            currentWallpaperSection

            Divider()

            HStack {
                Image(systemName: "heart.fill")
                    .foregroundColor(.pink)
                Text("Favorites")
                    .font(.headline)

                Spacer()

                Link(destination: URL(string: "wallnetic://nextWallpaper")!) {
                    Label("Next", systemImage: "forward.fill")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.2))
                        .cornerRadius(6)
                }
            }

            if entry.favorites.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(entry.favorites.prefix(SharedConstants.maxFavorites)) { wallpaper in
                        wallpaperThumbnail(wallpaper)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var currentWallpaperSection: some View {
        HStack(spacing: 12) {
            ZStack {
                if let image = entry.currentWallpaper?.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(
                        colors: [.purple.opacity(0.6), .blue.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .frame(width: 80, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.currentWallpaper?.name ?? "No Wallpaper")
                    .font(.headline)
                    .lineLimit(1)
                Text(entry.isPlaying ? "Playing" : "Paused")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Link(destination: URL(string: "wallnetic://playPause")!) {
                Image(systemName: entry.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.accentColor)
            }
        }
    }

    private func wallpaperThumbnail(_ wallpaper: WidgetWallpaperInfo) -> some View {
        Link(destination: URL(string: "wallnetic://setWallpaper?id=\(wallpaper.id.uuidString)")!) {
            thumbnailContent(wallpaper)
        }
    }

    private func thumbnailContent(_ wallpaper: WidgetWallpaperInfo) -> some View {
        ZStack {
            if let image = wallpaper.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [.gray.opacity(0.3), .gray.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            if wallpaper.id == entry.currentWallpaper?.id {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 3)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                            .background(Circle().fill(.white))
                            .padding(4)
                    }
                }
            }
        }
        .frame(height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.slash")
                .font(.title)
                .foregroundColor(.secondary)
            Text("No favorites yet")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Add favorites in the app")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}
