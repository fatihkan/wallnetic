import Foundation

/// A collection of wallpapers
struct WallpaperCollection: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var icon: String
    var wallpaperIds: [UUID]
    let dateCreated: Date
    var dateModified: Date

    init(name: String, icon: String = "folder.fill", wallpaperIds: [UUID] = []) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.wallpaperIds = wallpaperIds
        self.dateCreated = Date()
        self.dateModified = Date()
    }

    // MARK: - Helpers

    var wallpaperCount: Int {
        wallpaperIds.count
    }

    mutating func addWallpaper(_ wallpaper: Wallpaper) {
        if !wallpaperIds.contains(wallpaper.id) {
            wallpaperIds.append(wallpaper.id)
            dateModified = Date()
        }
    }

    mutating func removeWallpaper(_ wallpaper: Wallpaper) {
        wallpaperIds.removeAll { $0 == wallpaper.id }
        dateModified = Date()
    }

    func contains(_ wallpaper: Wallpaper) -> Bool {
        wallpaperIds.contains(wallpaper.id)
    }
}

// MARK: - Default Collections

extension WallpaperCollection {
    /// Available collection icons
    static let availableIcons = [
        "folder.fill",
        "star.fill",
        "heart.fill",
        "photo.fill",
        "film.fill",
        "sparkles",
        "moon.stars.fill",
        "sun.max.fill",
        "leaf.fill",
        "flame.fill",
        "bolt.fill",
        "paintbrush.fill",
        "wand.and.stars",
        "mountain.2.fill",
        "building.2.fill"
    ]
}
