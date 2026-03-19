import Foundation
import WidgetKit

/// Manages shared data between the main app and widget extension via App Groups
class SharedDataManager {
    static let shared = SharedDataManager()

    // MARK: - Constants

    /// App Group identifier for shared container
    static let appGroupIdentifier = "group.com.wallnetic.shared"

    /// UserDefaults keys for shared data
    private enum Keys {
        static let currentWallpaperID = "currentWallpaperID"
        static let currentWallpaperName = "currentWallpaperName"
        static let currentWallpaperThumbnail = "currentWallpaperThumbnail"
        static let isPlaying = "isPlaying"
        static let favoriteWallpapers = "favoriteWallpapers"
        static let recentWallpapers = "recentWallpapers"
        static let lastUpdated = "lastUpdated"
    }

    // MARK: - Properties

    /// Shared UserDefaults for App Group
    private let sharedDefaults: UserDefaults?

    /// Shared container URL for files
    var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier)
    }

    /// Directory for shared thumbnails
    var thumbnailsDirectory: URL? {
        sharedContainerURL?.appendingPathComponent("Thumbnails", isDirectory: true)
    }

    // MARK: - Initialization

    private init() {
        sharedDefaults = UserDefaults(suiteName: Self.appGroupIdentifier)

        // Create thumbnails directory if needed
        if let thumbnailsDir = thumbnailsDirectory {
            try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Current Wallpaper

    /// Updates the current wallpaper information in shared storage
    func updateCurrentWallpaper(id: UUID?, name: String?, thumbnailData: Data?) {
        sharedDefaults?.set(id?.uuidString, forKey: Keys.currentWallpaperID)
        sharedDefaults?.set(name, forKey: Keys.currentWallpaperName)
        sharedDefaults?.set(thumbnailData, forKey: Keys.currentWallpaperThumbnail)
        sharedDefaults?.set(Date(), forKey: Keys.lastUpdated)

        // Notify widget to refresh
        reloadWidgetTimelines()
    }

    /// Gets the current wallpaper ID
    var currentWallpaperID: UUID? {
        guard let idString = sharedDefaults?.string(forKey: Keys.currentWallpaperID) else {
            return nil
        }
        return UUID(uuidString: idString)
    }

    /// Gets the current wallpaper name
    var currentWallpaperName: String? {
        sharedDefaults?.string(forKey: Keys.currentWallpaperName)
    }

    /// Gets the current wallpaper thumbnail data
    var currentWallpaperThumbnail: Data? {
        sharedDefaults?.data(forKey: Keys.currentWallpaperThumbnail)
    }

    // MARK: - Playback State

    /// Updates the playback state
    func updatePlaybackState(isPlaying: Bool) {
        sharedDefaults?.set(isPlaying, forKey: Keys.isPlaying)
        sharedDefaults?.set(Date(), forKey: Keys.lastUpdated)

        reloadWidgetTimelines()
    }

    /// Gets the current playback state
    var isPlaying: Bool {
        sharedDefaults?.bool(forKey: Keys.isPlaying) ?? false
    }

    // MARK: - Favorite Wallpapers

    /// Lightweight wallpaper info for widget display
    struct WidgetWallpaper: Codable, Identifiable {
        let id: UUID
        let name: String
        let thumbnailPath: String?

        var thumbnailURL: URL? {
            guard let path = thumbnailPath else { return nil }
            return SharedDataManager.shared.thumbnailsDirectory?.appendingPathComponent(path)
        }
    }

    /// Updates the favorite wallpapers list
    func updateFavoriteWallpapers(_ wallpapers: [WidgetWallpaper]) {
        if let data = try? JSONEncoder().encode(wallpapers) {
            sharedDefaults?.set(data, forKey: Keys.favoriteWallpapers)
        }
        sharedDefaults?.set(Date(), forKey: Keys.lastUpdated)

        reloadWidgetTimelines()
    }

    /// Gets the favorite wallpapers
    var favoriteWallpapers: [WidgetWallpaper] {
        guard let data = sharedDefaults?.data(forKey: Keys.favoriteWallpapers),
              let wallpapers = try? JSONDecoder().decode([WidgetWallpaper].self, from: data) else {
            return []
        }
        return wallpapers
    }

    // MARK: - Recent Wallpapers

    /// Updates the recent wallpapers list
    func updateRecentWallpapers(_ wallpapers: [WidgetWallpaper]) {
        if let data = try? JSONEncoder().encode(wallpapers) {
            sharedDefaults?.set(data, forKey: Keys.recentWallpapers)
        }
        sharedDefaults?.set(Date(), forKey: Keys.lastUpdated)

        reloadWidgetTimelines()
    }

    /// Gets the recent wallpapers
    var recentWallpapers: [WidgetWallpaper] {
        guard let data = sharedDefaults?.data(forKey: Keys.recentWallpapers),
              let wallpapers = try? JSONDecoder().decode([WidgetWallpaper].self, from: data) else {
            return []
        }
        return wallpapers
    }

    // MARK: - Thumbnail Management

    /// Saves a thumbnail to the shared container
    func saveThumbnail(data: Data, for wallpaperID: UUID) -> String? {
        guard let thumbnailsDir = thumbnailsDirectory else { return nil }

        let filename = "\(wallpaperID.uuidString).jpg"
        let fileURL = thumbnailsDir.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL)
            return filename
        } catch {
            print("[SharedDataManager] Failed to save thumbnail: \(error)")
            return nil
        }
    }

    /// Loads a thumbnail from the shared container
    func loadThumbnail(filename: String) -> Data? {
        guard let thumbnailsDir = thumbnailsDirectory else { return nil }

        let fileURL = thumbnailsDir.appendingPathComponent(filename)
        return try? Data(contentsOf: fileURL)
    }

    /// Removes a thumbnail from the shared container
    func removeThumbnail(filename: String) {
        guard let thumbnailsDir = thumbnailsDirectory else { return }

        let fileURL = thumbnailsDir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Widget Communication

    /// Reloads all widget timelines
    func reloadWidgetTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Gets the last update timestamp
    var lastUpdated: Date? {
        sharedDefaults?.object(forKey: Keys.lastUpdated) as? Date
    }

    // MARK: - Widget Actions (for URL scheme handling)

    /// Action types that can be triggered from the widget
    enum WidgetAction: String {
        case setWallpaper = "setWallpaper"
        case playPause = "playPause"
        case nextWallpaper = "nextWallpaper"
    }

    /// Parses a widget action URL
    /// Format: wallnetic://action?id=xxx
    static func parseWidgetURL(_ url: URL) -> (action: WidgetAction, wallpaperID: UUID?)? {
        guard url.scheme == "wallnetic",
              let actionString = url.host,
              let action = WidgetAction(rawValue: actionString) else {
            return nil
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let wallpaperID = components?.queryItems?.first(where: { $0.name == "id" })?.value
            .flatMap { UUID(uuidString: $0) }

        return (action, wallpaperID)
    }

    /// Creates a URL for a widget action
    static func createWidgetURL(action: WidgetAction, wallpaperID: UUID? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = "wallnetic"
        components.host = action.rawValue

        if let id = wallpaperID {
            components.queryItems = [URLQueryItem(name: "id", value: id.uuidString)]
        }

        return components.url
    }
}
