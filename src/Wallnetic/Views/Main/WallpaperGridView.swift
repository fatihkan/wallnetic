import SwiftUI

struct WallpaperGridView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @Binding var selectedWallpaper: Wallpaper?
    let searchText: String
    let filter: SidebarSelection

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 16)
    ]

    var filteredWallpapers: [Wallpaper] {
        var wallpapers = wallpaperManager.wallpapers

        // Apply sidebar filter
        switch filter {
        case .all:
            break // Show all wallpapers
        case .favorites:
            wallpapers = wallpapers.filter { $0.isFavorite }
        case .recent:
            // Show wallpapers added in the last 7 days, sorted by date
            let oneWeekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            wallpapers = wallpapers
                .filter { $0.dateAdded > oneWeekAgo }
                .sorted { $0.dateAdded > $1.dateAdded }
        case .aiGenerate, .aiHistory, .collections, .collection:
            break // Not used in grid view
        }

        // Apply search filter
        if !searchText.isEmpty {
            wallpapers = wallpapers.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }

        return wallpapers
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(filteredWallpapers) { wallpaper in
                    WallpaperCard(
                        wallpaper: wallpaper,
                        isSelected: selectedWallpaper?.id == wallpaper.id
                    )
                    .onTapGesture {
                        selectedWallpaper = wallpaper
                    }
                    .onTapGesture(count: 2) {
                        wallpaperManager.setWallpaper(wallpaper)
                    }
                    .contextMenu {
                        WallpaperContextMenu(wallpaper: wallpaper)
                    }
                }
            }
            .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor))

        // Bottom bar with selected wallpaper info
        if let selected = selectedWallpaper {
            SelectedWallpaperBar(wallpaper: selected)
        }
    }
}

// MARK: - Wallpaper Card

struct WallpaperCard: View {
    let wallpaper: Wallpaper
    let isSelected: Bool
    @State private var thumbnail: NSImage?
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .aspectRatio(16/9, contentMode: .fit)
                        .overlay {
                            ProgressView()
                        }
                }

                // Duration badge
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(wallpaper.formattedDuration)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial)
                            .cornerRadius(4)
                            .padding(8)
                    }
                }

                // Hover play icon
                if isHovering {
                    Color.black.opacity(0.3)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                }
            }
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(wallpaper.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text("\(wallpaper.formattedResolution) • \(wallpaper.formattedFileSize)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .task {
            thumbnail = await wallpaper.generateThumbnail()
        }
    }
}

// MARK: - Context Menu

struct WallpaperContextMenu: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    let wallpaper: Wallpaper

    var body: some View {
        Button {
            wallpaperManager.setWallpaper(wallpaper)
        } label: {
            Label("Set as Wallpaper", systemImage: "photo.on.rectangle")
        }

        Button {
            wallpaperManager.toggleFavorite(wallpaper)
        } label: {
            Label(
                wallpaper.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: wallpaper.isFavorite ? "heart.fill" : "heart"
            )
        }

        Divider()

        Button {
            NSWorkspace.shared.activateFileViewerSelecting([wallpaper.url])
        } label: {
            Label("Show in Finder", systemImage: "folder")
        }

        Divider()

        Button(role: .destructive) {
            wallpaperManager.removeWallpaper(wallpaper)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - Selected Wallpaper Bar

struct SelectedWallpaperBar: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    let wallpaper: Wallpaper

    var body: some View {
        HStack {
            // Preview thumbnail
            AsyncThumbnailView(wallpaper: wallpaper, size: CGSize(width: 80, height: 45))
                .cornerRadius(4)

            VStack(alignment: .leading) {
                Text(wallpaper.name)
                    .fontWeight(.medium)
                Text("\(wallpaper.formattedResolution) • \(wallpaper.formattedDuration)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Apply button
            Button {
                wallpaperManager.setWallpaper(wallpaper)
            } label: {
                Text("Apply Wallpaper")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .background(.bar)
    }
}

// MARK: - Async Thumbnail View

struct AsyncThumbnailView: View {
    let wallpaper: Wallpaper
    let size: CGSize
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: size.width, height: size.height)
            }
        }
        .task {
            thumbnail = await wallpaper.generateThumbnail(size: size)
        }
    }
}
