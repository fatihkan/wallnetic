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
        let sharedData = loadSharedData()
        let currentWallpaper = loadCurrentWallpaper(from: sharedData)
        let favorites = loadFavorites(from: sharedData)

        // Generate entries for the next 60 minutes (one per minute for clock updates)
        var entries: [WallpaperEntry] = []
        let now = Date()

        for minuteOffset in 0..<60 {
            let entryDate = Calendar.current.date(byAdding: .minute, value: minuteOffset, to: now) ?? now
            entries.append(WallpaperEntry(
                date: entryDate,
                currentWallpaper: currentWallpaper,
                isPlaying: sharedData.isPlaying,
                favorites: favorites
            ))
        }

        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
        completion(Timeline(entries: entries, policy: .after(nextUpdate)))
    }

    // MARK: - Data Loading

    private func createEntry() -> WallpaperEntry {
        let sharedData = loadSharedData()
        return WallpaperEntry(
            date: .now,
            currentWallpaper: loadCurrentWallpaper(from: sharedData),
            isPlaying: sharedData.isPlaying,
            favorites: loadFavorites(from: sharedData)
        )
    }

    private func loadCurrentWallpaper(from sharedData: SharedWidgetData) -> WidgetWallpaperInfo? {
        guard let idString = sharedData.currentWallpaperID,
              let id = UUID(uuidString: idString) else { return nil }
        let name = sharedData.currentWallpaperName ?? "Unknown"
        let image = loadThumbnailImage(sharedData.currentThumbnailPath)
        return WidgetWallpaperInfo(id: id, name: name, image: image)
    }

    private func loadFavorites(from sharedData: SharedWidgetData) -> [WidgetWallpaperInfo] {
        Array(sharedData.favorites.prefix(SharedConstants.maxFavorites).map { fav in
            WidgetWallpaperInfo(id: fav.id, name: fav.name, image: loadThumbnailImage(fav.thumbnailPath))
        })
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
