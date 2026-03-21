import SwiftUI
import WidgetKit

/// Medium widget showing 4 favorite wallpapers in a grid
struct MediumWidgetView: View {
    let entry: WallpaperEntry

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "photo.stack")
                    .foregroundColor(.secondary)
                Text("Favorites")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Link(destination: URL(string: "wallnetic://playPause")!) {
                    Image(systemName: entry.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 4)

            if entry.favorites.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(entry.favorites.prefix(4)) { wallpaper in
                        wallpaperThumbnail(wallpaper)
                    }
                }
            }
        }
        .padding(12)
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
            }
        }
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "heart.slash")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("No favorites")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
