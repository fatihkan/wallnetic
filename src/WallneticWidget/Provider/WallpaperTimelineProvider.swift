import WidgetKit
import SwiftUI

/// Timeline entry for the wallpaper widget
struct WallpaperEntry: TimelineEntry {
    let date: Date
    let currentWallpaper: WidgetWallpaperInfo?
    let isPlaying: Bool
    let favorites: [WidgetWallpaperInfo]
}

/// Widget wallpaper info with pre-loaded image
struct WidgetWallpaperInfo: Identifiable {
    let id: UUID
    let name: String
    let image: NSImage?
}

/// Provides timeline entries for the widget
struct WallpaperTimelineProvider: TimelineProvider {
    typealias Entry = WallpaperEntry

    private var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedConstants.appGroupIdentifier)
    }

    private var sharedDataFileURL: URL? {
        sharedContainerURL?.appendingPathComponent(SharedConstants.sharedDataFilename)
    }

    private var thumbnailsDirectory: URL? {
        sharedContainerURL?.appendingPathComponent("Thumbnails", isDirectory: true)
    }

    // MARK: - TimelineProvider

    func placeholder(in context: Context) -> WallpaperEntry {
        WallpaperEntry(date: .now, currentWallpaper: nil, isPlaying: false, favorites: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (WallpaperEntry) -> Void) {
        completion(createEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WallpaperEntry>) -> Void) {
        let entry = createEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    // MARK: - Data Loading

    private func createEntry() -> WallpaperEntry {
        let sharedData = loadSharedData()

        // Load current wallpaper with pre-loaded image
        var currentWallpaper: WidgetWallpaperInfo? = nil
        if let idString = sharedData.currentWallpaperID,
           let id = UUID(uuidString: idString) {
            let name = sharedData.currentWallpaperName ?? "Unknown"
            let image = loadThumbnailImage(sharedData.currentThumbnailPath)
            currentWallpaper = WidgetWallpaperInfo(id: id, name: name, image: image)
        }

        // Load favorites with pre-loaded images
        let favorites = sharedData.favorites.prefix(SharedConstants.maxFavorites).map { fav in
            WidgetWallpaperInfo(
                id: fav.id,
                name: fav.name,
                image: loadThumbnailImage(fav.thumbnailPath)
            )
        }

        return WallpaperEntry(
            date: .now,
            currentWallpaper: currentWallpaper,
            isPlaying: sharedData.isPlaying,
            favorites: Array(favorites)
        )
    }

    private func loadSharedData() -> SharedWidgetData {
        guard let fileURL = sharedDataFileURL,
              FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let sharedData = try? JSONDecoder().decode(SharedWidgetData.self, from: data) else {
            return SharedWidgetData()
        }
        return sharedData
    }

    /// Pre-loads a thumbnail image from the shared container
    private func loadThumbnailImage(_ path: String?) -> NSImage? {
        guard let path = path, let dir = thumbnailsDirectory else { return nil }
        let fileURL = dir.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return NSImage(data: data)
    }
}
