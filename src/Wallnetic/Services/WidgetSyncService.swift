import Foundation
import AppKit

/// Handles all widget synchronization: current wallpaper, playback state, favorites.
final class WidgetSyncService {
    static let shared = WidgetSyncService()

    private init() {}

    // MARK: - Sync All

    func syncAll(current: Wallpaper?, isPlaying: Bool, wallpapers: [Wallpaper]) {
        Task {
            await syncCurrentWallpaper(current)
            syncPlaybackState(isPlaying: isPlaying)
            await syncFavorites(wallpapers.filter { $0.isFavorite })
        }
    }

    // MARK: - Current Wallpaper

    func syncCurrentWallpaper(_ wallpaper: Wallpaper?) async {
        guard let wallpaper else {
            SharedDataManager.shared.updateCurrentWallpaper(id: nil, name: nil, thumbnailPath: nil)
            return
        }

        var thumbnailPath: String?
        if let thumbnail = await ThumbnailCache.shared.thumbnail(for: wallpaper.url, size: CGSize(width: 200, height: 120)) {
            if let tiffData = thumbnail.tiffRepresentation,
               let bitmapRep = NSBitmapImageRep(data: tiffData),
               let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
                thumbnailPath = SharedDataManager.shared.saveThumbnail(data: jpegData, for: wallpaper.id)
            }
        }

        SharedDataManager.shared.updateCurrentWallpaper(
            id: wallpaper.id,
            name: wallpaper.name,
            thumbnailPath: thumbnailPath
        )
    }

    // MARK: - Playback State

    func syncPlaybackState(isPlaying: Bool) {
        SharedDataManager.shared.updatePlaybackState(isPlaying: isPlaying)
    }

    // MARK: - Favorites

    func syncFavorites(_ favorites: [Wallpaper]) async {
        var widgetWallpapers: [SharedWidgetWallpaper] = []

        for wallpaper in favorites.prefix(SharedConstants.maxFavorites) {
            var thumbnailPath: String?
            if let thumbnail = await ThumbnailCache.shared.thumbnail(for: wallpaper.url, size: CGSize(width: 150, height: 90)) {
                if let tiffData = thumbnail.tiffRepresentation,
                   let bitmapRep = NSBitmapImageRep(data: tiffData),
                   let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) {
                    thumbnailPath = SharedDataManager.shared.saveThumbnail(data: jpegData, for: wallpaper.id)
                }
            }

            widgetWallpapers.append(SharedWidgetWallpaper(
                id: wallpaper.id,
                name: wallpaper.name,
                thumbnailPath: thumbnailPath
            ))
        }

        SharedDataManager.shared.updateFavoriteWallpapers(widgetWallpapers)
    }
}
