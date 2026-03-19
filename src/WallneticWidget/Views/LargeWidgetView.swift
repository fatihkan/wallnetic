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
            // Current wallpaper section
            currentWallpaperSection

            Divider()

            // Favorites header
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundColor(.pink)
                Text("Favorites")
                    .font(.headline)

                Spacer()

                // Next wallpaper button
                if #available(macOS 14.0, *) {
                    Button(intent: NextWallpaperIntent()) {
                        Label("Next", systemImage: "forward.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Link(destination: URL(string: "wallnetic://nextWallpaper")!) {
                        Label("Next", systemImage: "forward.fill")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.secondary.opacity(0.2))
                            .cornerRadius(6)
                    }
                }
            }

            // Favorites grid
            if entry.favorites.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(entry.favorites.prefix(6)) { wallpaper in
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
            // Current thumbnail
            ZStack {
                if let wallpaper = entry.currentWallpaper,
                   let thumbnailURL = wallpaper.thumbnailURL,
                   let imageData = try? Data(contentsOf: thumbnailURL),
                   let nsImage = NSImage(data: imageData) {
                    Image(nsImage: nsImage)
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

            // Info and controls
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.currentWallpaper?.name ?? "No Wallpaper")
                    .font(.headline)
                    .lineLimit(1)

                Text(entry.isPlaying ? "Playing" : "Paused")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Play/pause button
            if #available(macOS 14.0, *) {
                Button(intent: PlayPauseIntent()) {
                    Image(systemName: entry.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            } else {
                Link(destination: URL(string: "wallnetic://playPause")!) {
                    Image(systemName: entry.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.accentColor)
                }
            }
        }
    }

    private func wallpaperThumbnail(_ wallpaper: WidgetWallpaperInfo) -> some View {
        Group {
            if #available(macOS 14.0, *) {
                Button(intent: SetWallpaperIntent(wallpaperID: wallpaper.id.uuidString)) {
                    thumbnailContent(wallpaper)
                }
                .buttonStyle(.plain)
            } else {
                Link(destination: URL(string: "wallnetic://setWallpaper?id=\(wallpaper.id.uuidString)")!) {
                    thumbnailContent(wallpaper)
                }
            }
        }
    }

    private func thumbnailContent(_ wallpaper: WidgetWallpaperInfo) -> some View {
        ZStack {
            if let thumbnailURL = wallpaper.thumbnailURL,
               let imageData = try? Data(contentsOf: thumbnailURL),
               let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [.gray.opacity(0.3), .gray.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            // Current indicator
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
