import Foundation

/// Shared data model written by the app, read by the widget.
/// Both sides must use identical Codable layout — keep this file
/// included in both the Wallnetic and WallneticWidget targets.
struct SharedWidgetData: Codable {
    var currentWallpaperID: String?
    var currentWallpaperName: String?
    var currentThumbnailPath: String?
    var isPlaying: Bool
    var favorites: [SharedWidgetWallpaper]
    var lastUpdated: Date

    init() {
        self.isPlaying = false
        self.favorites = []
        self.lastUpdated = Date()
    }
}

/// Lightweight wallpaper info for widget display
struct SharedWidgetWallpaper: Codable, Identifiable {
    let id: UUID
    let name: String
    let thumbnailPath: String?
}

/// Constants shared between app and widget
enum SharedConstants {
    static let appGroupIdentifier = "group.com.wallnetic.shared"
    static let sharedDataFilename = "WidgetData.json"
    static let maxFavorites = 6
}
