import WidgetKit
import SwiftUI

/// Timeline entry for the wallpaper widget
struct WallpaperEntry: TimelineEntry {
    let date: Date
    let currentWallpaper: WidgetWallpaperInfo?
    let isPlaying: Bool
    let favorites: [WidgetWallpaperInfo]
}

/// Lightweight wallpaper info for widget display
struct WidgetWallpaperInfo: Identifiable, Codable {
    let id: UUID
    let name: String
    let thumbnailPath: String?

    var thumbnailURL: URL? {
        guard let path = thumbnailPath,
              let containerURL = FileManager.default.containerURL(
                  forSecurityApplicationGroupIdentifier: "group.com.wallnetic.shared"
              ) else {
            return nil
        }
        return containerURL.appendingPathComponent("Thumbnails").appendingPathComponent(path)
    }
}

/// Provides timeline entries for the widget
struct WallpaperTimelineProvider: TimelineProvider {
    typealias Entry = WallpaperEntry

    /// App Group identifier
    private let appGroupID = "group.com.wallnetic.shared"

    /// Shared UserDefaults
    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    // MARK: - TimelineProvider

    func placeholder(in context: Context) -> WallpaperEntry {
        WallpaperEntry(
            date: .now,
            currentWallpaper: nil,
            isPlaying: false,
            favorites: []
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WallpaperEntry) -> Void) {
        let entry = createEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WallpaperEntry>) -> Void) {
        let entry = createEntry()

        // Refresh every 15 minutes or when data changes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))

        completion(timeline)
    }

    // MARK: - Data Loading

    private func createEntry() -> WallpaperEntry {
        let currentWallpaper = loadCurrentWallpaper()
        let isPlaying = sharedDefaults?.bool(forKey: "isPlaying") ?? false
        let favorites = loadFavorites()

        return WallpaperEntry(
            date: .now,
            currentWallpaper: currentWallpaper,
            isPlaying: isPlaying,
            favorites: favorites
        )
    }

    private func loadCurrentWallpaper() -> WidgetWallpaperInfo? {
        guard let idString = sharedDefaults?.string(forKey: "currentWallpaperID"),
              let id = UUID(uuidString: idString) else {
            return nil
        }

        let name = sharedDefaults?.string(forKey: "currentWallpaperName") ?? "Unknown"

        // Try to get thumbnail path
        let thumbnailPath = "\(id.uuidString).jpg"

        return WidgetWallpaperInfo(id: id, name: name, thumbnailPath: thumbnailPath)
    }

    private func loadFavorites() -> [WidgetWallpaperInfo] {
        guard let data = sharedDefaults?.data(forKey: "favoriteWallpapers"),
              let favorites = try? JSONDecoder().decode([WidgetWallpaperInfo].self, from: data) else {
            return []
        }
        return Array(favorites.prefix(8)) // Max 8 for large widget
    }
}
