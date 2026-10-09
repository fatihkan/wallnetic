import Foundation
import WidgetKit
import Darwin

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

    /// Cleanup must know which thumbnails the widget still references. Unlike
    /// the display fallback above, an unreadable record is not an empty record.
    /// Called off the main thread by storage scans and cleanup.
    func readSharedDataForStorage() throws -> SharedWidgetData {
        guard let url = sharedDataFileURL else { return SharedWidgetData() }
        return try Self.readStorageReferences(at: url)
    }

    static func readStorageReferences(at url: URL) throws -> SharedWidgetData {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0 && errno == ENOENT { return SharedWidgetData() }
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size <= 1_048_576 else { throw StorageError.unsafeFile }
        let data = try handle.read(upToCount: 1_048_577) ?? Data()
        guard data.count <= 1_048_576 else { throw StorageError.unsafeFile }
        return try JSONDecoder().decode(SharedWidgetData.self, from: data)
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
