import Foundation
import WidgetKit

/// Manages shared data between the main app and widget extension via App Groups.
/// Uses file-based JSON storage for macOS sandbox compatibility.
class SharedDataManager {
    static let shared = SharedDataManager()

    // MARK: - Properties

    var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedConstants.appGroupIdentifier)
    }

    private var sharedDataFileURL: URL? {
        sharedContainerURL?.appendingPathComponent(SharedConstants.sharedDataFilename)
    }

    var thumbnailsDirectory: URL? {
        sharedContainerURL?.appendingPathComponent("Thumbnails", isDirectory: true)
    }

    // MARK: - Initialization

    private init() {
        if let thumbnailsDir = thumbnailsDirectory {
            try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
        }
        let containerPath = sharedContainerURL?.path ?? "nil"
        Log.shared.info("Container: \(containerPath, privacy: .public)")
    }

    // MARK: - File-Based Read/Write

    func readSharedData() -> SharedWidgetData {
        guard let fileURL = sharedDataFileURL,
              FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let sharedData = try? JSONDecoder().decode(SharedWidgetData.self, from: data) else {
            return SharedWidgetData()
        }
        return sharedData
    }

    private func writeSharedData(_ sharedData: SharedWidgetData) {
        guard let fileURL = sharedDataFileURL else { return }
        do {
            let data = try JSONEncoder().encode(sharedData)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.shared.error("Write error: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Current Wallpaper

    func updateCurrentWallpaper(id: UUID?, name: String?, thumbnailPath: String?) {
        var data = readSharedData()
        data.currentWallpaperID = id?.uuidString
        data.currentWallpaperName = name
        data.currentThumbnailPath = thumbnailPath
        data.lastUpdated = Date()
        writeSharedData(data)
        reloadWidgetTimelines()
    }

    // MARK: - Playback State

    func updatePlaybackState(isPlaying: Bool) {
        var data = readSharedData()
        data.isPlaying = isPlaying
        data.lastUpdated = Date()
        writeSharedData(data)
        reloadWidgetTimelines()
    }

    // MARK: - Favorites

    func updateFavoriteWallpapers(_ wallpapers: [SharedWidgetWallpaper]) {
        var data = readSharedData()
        data.favorites = wallpapers
        data.lastUpdated = Date()
        writeSharedData(data)
        Log.shared.info("Saved \(wallpapers.count) favorites")
        reloadWidgetTimelines()
    }

    // MARK: - Thumbnails

    func saveThumbnail(data: Data, for wallpaperID: UUID) -> String? {
        guard let thumbnailsDir = thumbnailsDirectory else { return nil }
        let filename = "\(wallpaperID.uuidString).jpg"
        let fileURL = thumbnailsDir.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL)
            return filename
        } catch {
            Log.shared.error("Thumbnail save error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Widget

    func reloadWidgetTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - URL Parsing

    enum WidgetAction: String {
        case setWallpaper, playPause, nextWallpaper
    }

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
}
