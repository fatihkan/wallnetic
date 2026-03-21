import Foundation
import SwiftUI
import Combine
import os.log

#if canImport(WidgetKit)
import WidgetKit
#endif

/// Import errors
enum WallpaperImportError: LocalizedError {
    case duplicate(String)

    var errorDescription: String? {
        switch self {
        case .duplicate(let name):
            return "'\(name)' is already in your library"
        }
    }
}

/// Wallpaper mode for multi-monitor setups
enum WallpaperMode: String, CaseIterable {
    case same = "same"
    case different = "different"

    var displayName: String {
        switch self {
        case .same: return "Same on all displays"
        case .different: return "Different per display"
        }
    }
}

/// Central manager for wallpaper state and settings
class WallpaperManager: ObservableObject {
    static let shared = WallpaperManager()

    // MARK: - Published Properties

    @Published var wallpapers: [Wallpaper] = []
    @Published var currentWallpaper: Wallpaper?
    @Published var isPlaying: Bool = false
    @Published var wallpaperMode: WallpaperMode = .same

    /// Per-screen wallpaper assignments (screenName -> wallpaperID)
    @Published var screenWallpapers: [String: UUID] = [:]

    // Settings
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("pauseOnBattery") var pauseOnBattery: Bool = true
    @AppStorage("pauseOnFullscreen") var pauseOnFullscreen: Bool = true
    @AppStorage("shouldAutoResume") var shouldAutoResume: Bool = true
    @AppStorage("wallpaperModeRaw") private var wallpaperModeRaw: String = "same"
    @AppStorage("screenWallpapersData") private var screenWallpapersData: Data = Data()
    @AppStorage("useMetalRenderer") var useMetalRenderer: Bool = false
    @AppStorage("lastWallpaperURL") private var lastWallpaperURL: String = ""
    @AppStorage("favoriteWallpaperPaths") private var favoriteWallpaperPaths: String = ""

    // MARK: - Properties

    private let fileManager = FileManager.default

    private var libraryURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let wallneticDir = appSupport.appendingPathComponent("Wallnetic/Library", isDirectory: true)

        // Create directory if needed
        if !fileManager.fileExists(atPath: wallneticDir.path) {
            try? fileManager.createDirectory(at: wallneticDir, withIntermediateDirectories: true)
        }

        return wallneticDir
    }

    // MARK: - Initialization

    private init() {
        loadWallpapers()
        loadSettings()
        syncToWidget()
    }

    /// Load persisted settings
    private func loadSettings() {
        // Load wallpaper mode
        if let mode = WallpaperMode(rawValue: wallpaperModeRaw) {
            wallpaperMode = mode
        }

        // Load per-screen wallpaper assignments
        if !screenWallpapersData.isEmpty {
            if let decoded = try? JSONDecoder().decode([String: UUID].self, from: screenWallpapersData) {
                screenWallpapers = decoded
            }
        }

        // Restore last wallpaper after a short delay (to ensure wallpapers are loaded)
        if !lastWallpaperURL.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.restoreLastWallpaper()
            }
        }
    }

    /// Restore the last selected wallpaper
    private func restoreLastWallpaper() {
        guard !lastWallpaperURL.isEmpty else { return }

        let url = URL(fileURLWithPath: lastWallpaperURL)

        // Find the wallpaper in our library
        if let wallpaper = wallpapers.first(where: { $0.url.path == url.path }) {
            NSLog("[WallpaperManager] Restoring last wallpaper: %@", wallpaper.name)
            setWallpaper(wallpaper)

            // Auto-play after restore
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.isPlaying = true
                NotificationCenter.default.post(
                    name: .playbackStateDidChange,
                    object: true
                )
            }
        }
    }

    /// Save per-screen wallpaper assignments
    private func saveScreenWallpapers() {
        if let encoded = try? JSONEncoder().encode(screenWallpapers) {
            screenWallpapersData = encoded
        }
    }

    // MARK: - Library Management

    /// Gets the set of favorite wallpaper paths
    private var favoritePaths: Set<String> {
        get {
            Set(favoriteWallpaperPaths.split(separator: "\n").map(String.init))
        }
        set {
            favoriteWallpaperPaths = newValue.joined(separator: "\n")
        }
    }

    /// Loads all wallpapers from the library directory
    func loadWallpapers() {
        wallpapers = []
        let savedFavorites = favoritePaths

        guard let contents = try? fileManager.contentsOfDirectory(
            at: libraryURL,
            includingPropertiesForKeys: [.contentTypeKey],
            options: .skipsHiddenFiles
        ) else { return }

        for url in contents {
            if isVideoFile(url) {
                let isFavorite = savedFavorites.contains(url.path)
                let wallpaper = Wallpaper(url: url, isFavorite: isFavorite)
                wallpapers.append(wallpaper)
            }
        }

        print("Loaded \(wallpapers.count) wallpapers from library (\(savedFavorites.count) favorites)")
    }

    /// Checks if a file is a duplicate of an existing library item (by file size + name)
    func isDuplicate(of sourceURL: URL) -> Wallpaper? {
        let sourceSize = (try? fileManager.attributesOfItem(atPath: sourceURL.path))?[.size] as? Int64 ?? 0
        let sourceName = sourceURL.deletingPathExtension().lastPathComponent
        return wallpapers.first { $0.fileSize == sourceSize && $0.name == sourceName }
    }

    /// Imports a video file into the library
    func importVideo(from sourceURL: URL) async throws -> Wallpaper {
        print("[WallpaperManager] Importing video from: \(sourceURL.path)")

        // Duplicate detection
        if let existing = isDuplicate(of: sourceURL) {
            NSLog("[WallpaperManager] Duplicate detected: %@ matches %@", sourceURL.lastPathComponent, existing.name)
            throw WallpaperImportError.duplicate(existing.name)
        }

        let fileName = sourceURL.lastPathComponent
        let destURL = libraryURL.appendingPathComponent(fileName)

        // Check if file already exists
        if fileManager.fileExists(atPath: destURL.path) {
            // Generate unique name
            let uniqueName = UUID().uuidString + "_" + fileName
            let uniqueURL = libraryURL.appendingPathComponent(uniqueName)
            print("[WallpaperManager] File exists, using unique name: \(uniqueName)")
            try fileManager.copyItem(at: sourceURL, to: uniqueURL)
            print("[WallpaperManager] File copied successfully to: \(uniqueURL.path)")

            let wallpaper = Wallpaper(url: uniqueURL)
            await MainActor.run {
                wallpapers.append(wallpaper)
                print("[WallpaperManager] Wallpaper added to library. Total count: \(wallpapers.count)")
            }
            return wallpaper
        } else {
            try fileManager.copyItem(at: sourceURL, to: destURL)
            print("[WallpaperManager] File copied successfully to: \(destURL.path)")

            let wallpaper = Wallpaper(url: destURL)
            await MainActor.run {
                wallpapers.append(wallpaper)
                print("[WallpaperManager] Wallpaper added to library. Total count: \(wallpapers.count)")
            }
            return wallpaper
        }
    }

    /// Removes a wallpaper from the library
    func removeWallpaper(_ wallpaper: Wallpaper) {
        try? fileManager.removeItem(at: wallpaper.url)
        wallpapers.removeAll { $0.id == wallpaper.id }

        if currentWallpaper?.id == wallpaper.id {
            currentWallpaper = nil
        }

        // Update saved favorites
        saveFavoritePaths()

        // Sync to widget
        Task {
            await syncFavoritesToWidget()
    
        }
    }

    /// Toggles favorite status for a wallpaper
    func toggleFavorite(_ wallpaper: Wallpaper) {
        if let index = wallpapers.firstIndex(where: { $0.id == wallpaper.id }) {
            wallpapers[index].isFavorite.toggle()

            // Save favorite paths to persist across launches
            saveFavoritePaths()

            // Sync favorites to widget
            Task {
                await syncFavoritesToWidget()
        
            }
        }
    }

    /// Saves favorite wallpaper paths to UserDefaults
    private func saveFavoritePaths() {
        let paths = wallpapers.filter { $0.isFavorite }.map { $0.url.path }
        favoritePaths = Set(paths)
        NSLog("[WallpaperManager] Saved %d favorite paths", paths.count)
    }

    // MARK: - Playback

    /// Sets wallpaper for all screens (same mode)
    func setWallpaper(_ wallpaper: Wallpaper) {
        NSLog("[WallpaperManager] Setting wallpaper: %@", wallpaper.name)
        currentWallpaper = wallpaper

        // Save for persistence
        lastWallpaperURL = wallpaper.url.path

        // Auto-play when wallpaper is applied
        isPlaying = true

        NotificationCenter.default.post(
            name: .wallpaperDidChange,
            object: wallpaper
        )

        // Ensure playback state is synced
        NotificationCenter.default.post(
            name: .playbackStateDidChange,
            object: true
        )

        // Sync to widget
        Task {
            await syncCurrentWallpaperToWidget()
            syncPlaybackStateToWidget()
        }
    }

    /// Sets wallpaper for a specific screen (different mode)
    func setWallpaper(_ wallpaper: Wallpaper, for screen: NSScreen) {
        let screenName = screen.localizedName
        NSLog("[WallpaperManager] Setting wallpaper '%@' for screen: %@", wallpaper.name, screenName)

        screenWallpapers[screenName] = wallpaper.id
        saveScreenWallpapers()

        // Auto-play when wallpaper is applied
        isPlaying = true

        NotificationCenter.default.post(
            name: .screenWallpaperDidChange,
            object: ScreenWallpaperInfo(wallpaper: wallpaper, screen: screen)
        )

        // Ensure playback state is synced
        NotificationCenter.default.post(
            name: .playbackStateDidChange,
            object: true
        )
    }

    /// Gets wallpaper for a specific screen
    func wallpaper(for screen: NSScreen) -> Wallpaper? {
        guard let wallpaperID = screenWallpapers[screen.localizedName] else {
            return currentWallpaper // Fallback to global wallpaper
        }
        return wallpapers.first { $0.id == wallpaperID }
    }

    /// Sets wallpaper mode and applies changes
    func setWallpaperMode(_ mode: WallpaperMode) {
        wallpaperMode = mode
        wallpaperModeRaw = mode.rawValue

        if mode == .same, let wallpaper = currentWallpaper {
            // Apply current wallpaper to all screens
            NotificationCenter.default.post(
                name: .wallpaperDidChange,
                object: wallpaper
            )
        } else if mode == .different {
            // Apply per-screen wallpapers
            NotificationCenter.default.post(
                name: .applyScreenWallpapers,
                object: nil
            )
        }
    }

    func togglePlayback() {
        isPlaying.toggle()
        NotificationCenter.default.post(
            name: .playbackStateDidChange,
            object: isPlaying
        )

        // Sync playback state to widget
        syncPlaybackStateToWidget()

    }

    // MARK: - Helpers

    private func isVideoFile(_ url: URL) -> Bool {
        let videoExtensions = ["mp4", "mov", "m4v", "hevc"]
        return videoExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - Widget Integration

    /// Syncs current state to widget via SharedDataManager
    func syncToWidget() {
        // Skip if no wallpaper loaded yet (will re-sync after restore)
        guard currentWallpaper != nil else { return }

        Task {
            await syncCurrentWallpaperToWidget()
            syncPlaybackStateToWidget()
            await syncFavoritesToWidget()
        }
    }

    /// Syncs current wallpaper to widget
    private func syncCurrentWallpaperToWidget() async {
        guard let wallpaper = currentWallpaper else {
            SharedDataManager.shared.updateCurrentWallpaper(id: nil, name: nil, thumbnailPath: nil)
            return
        }

        // Generate and save thumbnail
        var thumbnailPath: String? = nil
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

    /// Syncs playback state to widget
    private func syncPlaybackStateToWidget() {
        SharedDataManager.shared.updatePlaybackState(isPlaying: isPlaying)
    }

    /// Syncs favorite wallpapers to widget
    private func syncFavoritesToWidget() async {
        let favorites = wallpapers.filter { $0.isFavorite }
        var widgetWallpapers: [SharedWidgetWallpaper] = []

        for wallpaper in favorites.prefix(SharedConstants.maxFavorites) {
            var thumbnailPath: String? = nil
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
        NSLog("[WallpaperManager] Synced %d favorites to widget", widgetWallpapers.count)
    }

    /// Cycles to the next wallpaper in the library
    func cycleToNextWallpaper() {
        guard !wallpapers.isEmpty else { return }

        if let current = currentWallpaper,
           let currentIndex = wallpapers.firstIndex(where: { $0.id == current.id }) {
            let nextIndex = (currentIndex + 1) % wallpapers.count
            setWallpaper(wallpapers[nextIndex])
        } else {
            setWallpaper(wallpapers[0])
        }
    }

    /// Handles URL scheme from widget
    func handleWidgetURL(_ url: URL) {
        NSLog("[WallpaperManager] handleWidgetURL: %@", url.absoluteString)

        guard let (action, wallpaperID) = SharedDataManager.parseWidgetURL(url) else {
            NSLog("[WallpaperManager] Failed to parse URL - scheme: %@, host: %@",
                  url.scheme ?? "nil", url.host ?? "nil")
            return
        }

        NSLog("[WallpaperManager] Parsed action: %@", action.rawValue)

        switch action {
        case .playPause:
            NSLog("[WallpaperManager] Executing playPause")
            togglePlayback()

        case .setWallpaper:
            if let id = wallpaperID,
               let wallpaper = wallpapers.first(where: { $0.id == id }) {
                NSLog("[WallpaperManager] Setting wallpaper: %@", wallpaper.name)
                setWallpaper(wallpaper)
            } else {
                NSLog("[WallpaperManager] Wallpaper not found for ID: %@", wallpaperID?.uuidString ?? "nil")
            }

        case .nextWallpaper:
            NSLog("[WallpaperManager] Cycling to next wallpaper")
            cycleToNextWallpaper()
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let wallpaperDidChange = Notification.Name("wallpaperDidChange")
    static let playbackStateDidChange = Notification.Name("playbackStateDidChange")
    static let screenWallpaperDidChange = Notification.Name("screenWallpaperDidChange")
    static let applyScreenWallpapers = Notification.Name("applyScreenWallpapers")
}

// MARK: - Screen Wallpaper Info

/// Information about a per-screen wallpaper change
struct ScreenWallpaperInfo {
    let wallpaper: Wallpaper
    let screen: NSScreen
}
