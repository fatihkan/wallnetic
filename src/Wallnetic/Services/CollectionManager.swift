import Foundation
import SwiftUI

/// Manager for wallpaper collections
class CollectionManager: ObservableObject {
    static let shared = CollectionManager()

    @Published private(set) var collections: [WallpaperCollection] = []

    private let defaults = UserDefaults.standard
    private let collectionsKey = "wallpaperCollections"

    private init() {
        loadCollections()
    }

    // MARK: - CRUD Operations

    /// Create a new collection
    func createCollection(name: String, icon: String = "folder.fill") -> WallpaperCollection {
        let collection = WallpaperCollection(name: name, icon: icon)
        collections.append(collection)
        saveCollections()
        return collection
    }

    /// Update a collection
    func updateCollection(_ collection: WallpaperCollection) {
        if let index = collections.firstIndex(where: { $0.id == collection.id }) {
            collections[index] = collection
            saveCollections()
        }
    }

    /// Delete a collection
    func deleteCollection(_ collection: WallpaperCollection) {
        collections.removeAll { $0.id == collection.id }
        saveCollections()
    }

    /// Rename a collection
    func renameCollection(_ collection: WallpaperCollection, to name: String) {
        if let index = collections.firstIndex(where: { $0.id == collection.id }) {
            collections[index].name = name
            collections[index].dateModified = Date()
            saveCollections()
        }
    }

    /// Change collection icon
    func changeIcon(_ collection: WallpaperCollection, to icon: String) {
        if let index = collections.firstIndex(where: { $0.id == collection.id }) {
            collections[index].icon = icon
            collections[index].dateModified = Date()
            saveCollections()
        }
    }

    // MARK: - Wallpaper Management

    /// Add wallpaper to collection
    func addWallpaper(_ wallpaper: Wallpaper, to collection: WallpaperCollection) {
        if let index = collections.firstIndex(where: { $0.id == collection.id }) {
            collections[index].addWallpaper(wallpaper)
            saveCollections()
        }
    }

    /// Remove wallpaper from collection
    func removeWallpaper(_ wallpaper: Wallpaper, from collection: WallpaperCollection) {
        if let index = collections.firstIndex(where: { $0.id == collection.id }) {
            collections[index].removeWallpaper(wallpaper)
            saveCollections()
        }
    }

    /// Get all collections containing a wallpaper
    func collections(containing wallpaper: Wallpaper) -> [WallpaperCollection] {
        collections.filter { $0.contains(wallpaper) }
    }

    /// Check if wallpaper is in any collection
    func isInCollection(_ wallpaper: Wallpaper) -> Bool {
        collections.contains { $0.contains(wallpaper) }
    }

    /// Get wallpapers in a collection
    func wallpapers(in collection: WallpaperCollection) -> [Wallpaper] {
        let allWallpapers = WallpaperManager.shared.wallpapers
        return collection.wallpaperIds.compactMap { id in
            allWallpapers.first { $0.id == id }
        }
    }

    // MARK: - Persistence

    private func loadCollections() {
        guard let data = defaults.data(forKey: collectionsKey) else { return }
        do {
            collections = try JSONDecoder().decode([WallpaperCollection].self, from: data)
        } catch {
            Log.app.error("CollectionManager decode failed; resetting saved collections. \(String(describing: error), privacy: .public)")
            defaults.removeObject(forKey: collectionsKey)
        }
    }

    private func saveCollections() {
        do {
            let encoded = try JSONEncoder().encode(collections)
            defaults.set(encoded, forKey: collectionsKey)
        } catch {
            Log.app.error("CollectionManager encode failed: \(String(describing: error), privacy: .public)")
        }
    }
}
