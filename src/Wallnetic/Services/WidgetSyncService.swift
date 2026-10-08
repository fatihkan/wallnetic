import Foundation
import AppKit

protocol WidgetDataWriting: AnyObject {
    func updateCurrentWallpaper(id: UUID?, name: String?, thumbnailPath: String?)
    func updatePlaybackState(isPlaying: Bool)
    func updateFavoriteWallpapers(_ wallpapers: [SharedWidgetWallpaper])
    func saveThumbnail(data: Data, for wallpaperID: UUID) -> String?
}

extension SharedDataManager: WidgetDataWriting {}

/// Handles all widget synchronization: current wallpaper, playback state, favorites.
final class WidgetSyncService {
    static let shared = WidgetSyncService()

    private let writer: () -> WidgetDataWriting
    private let thumbnail: (URL, CGSize) async -> NSImage?

    init(writer: @escaping () -> WidgetDataWriting = { SharedDataManager.shared },
         thumbnail: @escaping (URL, CGSize) async -> NSImage? = { url, size in
             await ThumbnailCache.shared.thumbnail(for: url, size: size)
         }) {
        self.writer = writer
        self.thumbnail = thumbnail
    }
    @MainActor private var currentRevision = 0
    @MainActor private var favoritesRevision = 0

    // MARK: - Sync All

    @discardableResult
    func syncAll(current: Wallpaper?, isPlaying: Bool, wallpapers: [Wallpaper]) -> Task<Void, Never> {
        Task { @MainActor in
            currentRevision += 1
            favoritesRevision += 1
            let currentToken = currentRevision
            let favoritesToken = favoritesRevision
            await syncCurrentWallpaper(current, revision: currentToken)
            if currentRevision == currentToken { syncPlaybackState(isPlaying: isPlaying) }
            await syncFavorites(wallpapers.filter { $0.isFavorite }, revision: favoritesToken)
        }
    }

    // MARK: - Current Wallpaper

    @MainActor
    func syncCurrentWallpaper(_ wallpaper: Wallpaper?) async {
        currentRevision += 1
        await syncCurrentWallpaper(wallpaper, revision: currentRevision)
    }

    @MainActor
    private func syncCurrentWallpaper(_ wallpaper: Wallpaper?, revision: Int) async {
        guard currentRevision == revision else { return }
        guard let wallpaper else {
            writer().updateCurrentWallpaper(id: nil, name: nil, thumbnailPath: nil)
            return
        }

        var thumbnailPath: String?
        if let thumbnail = await thumbnail(wallpaper.url, CGSize(width: 200, height: 120)) {
            if let tiffData = thumbnail.tiffRepresentation,
               let bitmapRep = NSBitmapImageRep(data: tiffData),
               let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
                thumbnailPath = writer().saveThumbnail(data: jpegData, for: wallpaper.id)
            }
        }

        guard currentRevision == revision else { return }
        writer().updateCurrentWallpaper(
            id: wallpaper.id,
            name: wallpaper.name,
            thumbnailPath: thumbnailPath
        )
    }

    // MARK: - Playback State

    func syncPlaybackState(isPlaying: Bool) {
        writer().updatePlaybackState(isPlaying: isPlaying)
    }

    // MARK: - Favorites

    @MainActor
    func syncFavorites(_ favorites: [Wallpaper]) async {
        favoritesRevision += 1
        await syncFavorites(favorites, revision: favoritesRevision)
    }

    @MainActor
    private func syncFavorites(_ favorites: [Wallpaper], revision: Int) async {
        guard favoritesRevision == revision else { return }
        var widgetWallpapers: [SharedWidgetWallpaper] = []

        for wallpaper in favorites.prefix(SharedConstants.maxFavorites) {
            guard favoritesRevision == revision else { return }
            var thumbnailPath: String?
            if let thumbnail = await thumbnail(wallpaper.url, CGSize(width: 150, height: 90)) {
                if let tiffData = thumbnail.tiffRepresentation,
                   let bitmapRep = NSBitmapImageRep(data: tiffData),
                   let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) {
                    thumbnailPath = writer().saveThumbnail(data: jpegData, for: wallpaper.id)
                }
            }

            widgetWallpapers.append(SharedWidgetWallpaper(
                id: wallpaper.id,
                name: wallpaper.name,
                thumbnailPath: thumbnailPath
            ))
        }

        guard favoritesRevision == revision else { return }
        writer().updateFavoriteWallpapers(widgetWallpapers)
    }
}
