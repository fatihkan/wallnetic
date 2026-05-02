import Foundation
import SwiftUI

/// Syncs wallpaper library settings across Macs via iCloud
class iCloudSyncManager: ObservableObject {
    static let shared = iCloudSyncManager()

    @AppStorage("icloud.enabled") var isEnabled: Bool = false

    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncDate: Date?

    enum SyncStatus: String {
        case idle = "Idle"
        case syncing = "Syncing..."
        case synced = "Synced"
        case error = "Error"
        case disabled = "Disabled"

        var icon: String {
            switch self {
            case .idle: return "icloud"
            case .syncing: return "arrow.triangle.2.circlepath.icloud"
            case .synced: return "checkmark.icloud"
            case .error: return "exclamationmark.icloud"
            case .disabled: return "icloud.slash"
            }
        }

        var color: Color {
            switch self {
            case .idle: return .secondary
            case .syncing: return .blue
            case .synced: return .green
            case .error: return .red
            case .disabled: return .secondary
            }
        }
    }

    // MARK: - Synced Keys

    private let kvStore = NSUbiquitousKeyValueStore.default

    /// Keys synced to iCloud
    private enum SyncKeys {
        static let favorites = "icloud.favorites"
        static let collections = "icloud.collections"
        static let lastWallpaper = "icloud.lastWallpaper"
        static let effectPreset = "icloud.effectPreset"
        static let lastSync = "icloud.lastSync"
    }

    private init() {
        if isEnabled { start() }
    }

    // MARK: - Control

    func start() {
        isEnabled = true
        syncStatus = .idle

        // Observe iCloud KV store changes
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore,
            queue: .main
        ) { [weak self] notification in
            self?.handleExternalChange(notification)
        }

        kvStore.synchronize()
        syncFromCloud()
    }

    func stop() {
        isEnabled = false
        syncStatus = .disabled
        NotificationCenter.default.removeObserver(self,
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore)
    }

    // MARK: - Sync To Cloud

    func syncToCloud() {
        guard isEnabled else { return }
        syncStatus = .syncing

        // Sync favorites (as wallpaper names since UUIDs change per install)
        let favoriteNames = WallpaperManager.shared.wallpapers
            .filter { $0.isFavorite }
            .map { $0.name }
        kvStore.set(favoriteNames, forKey: SyncKeys.favorites)

        // Sync current wallpaper name
        if let current = WallpaperManager.shared.currentWallpaper {
            kvStore.set(current.name, forKey: SyncKeys.lastWallpaper)
        }

        // Sync effect preset
        kvStore.set(WallpaperEffectsManager.shared.activePreset, forKey: SyncKeys.effectPreset)

        // Sync collections (as JSON)
        let collections = CollectionManager.shared.collections.map { collection -> [String: Any] in
            return [
                "name": collection.name,
                "icon": collection.icon,
                "wallpaperNames": collection.wallpaperIds.compactMap { id in
                    WallpaperManager.shared.wallpapers.first(where: { $0.id == id })?.name
                }
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: collections),
           let jsonString = String(data: data, encoding: .utf8) {
            kvStore.set(jsonString, forKey: SyncKeys.collections)
        }

        kvStore.set(Date().timeIntervalSince1970, forKey: SyncKeys.lastSync)
        kvStore.synchronize()

        syncStatus = .synced
        lastSyncDate = Date()
        Log.icloud.info("Synced to cloud: \(favoriteNames.count) favorites")
    }

    // MARK: - Sync From Cloud

    func syncFromCloud() {
        guard isEnabled else { return }
        syncStatus = .syncing

        // Restore favorites
        if let favoriteNames = kvStore.array(forKey: SyncKeys.favorites) as? [String] {
            for name in favoriteNames {
                if let wallpaper = WallpaperManager.shared.wallpapers.first(where: { $0.name == name }),
                   !wallpaper.isFavorite {
                    WallpaperManager.shared.toggleFavorite(wallpaper)
                }
            }
        }

        // Restore effect preset
        if let presetId = kvStore.string(forKey: SyncKeys.effectPreset),
           let preset = WallpaperEffectsManager.presets.first(where: { $0.id == presetId }) {
            WallpaperEffectsManager.shared.applyPreset(preset)
        }

        if let timestamp = kvStore.object(forKey: SyncKeys.lastSync) as? Double {
            lastSyncDate = Date(timeIntervalSince1970: timestamp)
        }

        syncStatus = .synced
        Log.icloud.info("Synced from cloud")
    }

    // MARK: - External Changes

    private func handleExternalChange(_ notification: Notification) {
        guard isEnabled else { return }
        Log.icloud.info("External change detected")
        syncFromCloud()
    }
}
