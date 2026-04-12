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
    @AppStorage("transitionStyle") var transitionStyle: String = "crossfade"
    @AppStorage("transitionDuration") var transitionDuration: Double = 0.5
    @AppStorage("lastWallpaperURL") private var lastWallpaperURL: String = ""
    @AppStorage("favoriteWallpaperPaths") private var favoriteWallpaperPaths: String = ""
    @AppStorage("customWallpaperTitles") private var customWallpaperTitlesData: String = ""
    @AppStorage("wallpaperColors") private var wallpaperColorsData: String = ""
    @AppStorage("wallpaperTags") private var wallpaperTagsData: String = ""

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

    private var fileWatcher: DispatchSourceFileSystemObject?

    private init() {
        loadWallpapers()
        loadSettings()
        syncToWidget()
        startFileWatching()
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

        // Apply saved custom titles, colors, and tags
        applyCustomTitles()
        applySavedColors()
        applySavedTags()

        print("Loaded \(wallpapers.count) wallpapers from library (\(savedFavorites.count) favorites)")

        // Extract colors in background for new wallpapers
        extractMissingColors()
    }

    /// Checks if a file is a duplicate of an existing library item (by file size + name)
    func isDuplicate(of sourceURL: URL) -> Wallpaper? {
        let sourceSize = (try? fileManager.attributesOfItem(atPath: sourceURL.path))?[.size] as? Int64 ?? 0
        let sourceName = sourceURL.deletingPathExtension().lastPathComponent
        return wallpapers.first { $0.fileSize == sourceSize && $0.name == sourceName }
    }

    /// Imports a video file into the library (supports GIF, WebM, WebP with auto-conversion)
    func importVideo(from sourceURL: URL) async throws -> Wallpaper {
        print("[WallpaperManager] Importing video from: \(sourceURL.path)")

        // Duplicate detection
        if let existing = isDuplicate(of: sourceURL) {
            NSLog("[WallpaperManager] Duplicate detected: %@ matches %@", sourceURL.lastPathComponent, existing.name)
            throw WallpaperImportError.duplicate(existing.name)
        }

        // Convert non-native formats (GIF, WebM, WebP) to MP4
        var importURL = sourceURL
        if VideoFormatConverter.shared.needsConversion(sourceURL) {
            NSLog("[WallpaperManager] Converting %@ to MP4...", sourceURL.pathExtension)
            importURL = try await VideoFormatConverter.shared.convertToMP4(source: sourceURL)
        }

        let originalName = sourceURL.deletingPathExtension().lastPathComponent
        let fileName = originalName + ".mp4"
        let destURL = libraryURL.appendingPathComponent(fileName)

        // Check if file already exists
        if fileManager.fileExists(atPath: destURL.path) {
            // Generate unique name
            let uniqueName = UUID().uuidString + "_" + fileName
            let uniqueURL = libraryURL.appendingPathComponent(uniqueName)
            print("[WallpaperManager] File exists, using unique name: \(uniqueName)")
            try fileManager.copyItem(at: importURL, to: uniqueURL)
            print("[WallpaperManager] File copied successfully to: \(uniqueURL.path)")

            let wallpaper = Wallpaper(url: uniqueURL)
            await MainActor.run {
                wallpapers.append(wallpaper)
                print("[WallpaperManager] Wallpaper added to library. Total count: \(wallpapers.count)")
            }
            postImportProcess(wallpaper)
            return wallpaper
        } else {
            try fileManager.copyItem(at: importURL, to: destURL)
            print("[WallpaperManager] File copied successfully to: \(destURL.path)")

            let wallpaper = Wallpaper(url: destURL)
            await MainActor.run {
                wallpapers.append(wallpaper)
                print("[WallpaperManager] Wallpaper added to library. Total count: \(wallpapers.count)")
            }
            postImportProcess(wallpaper)
            return wallpaper
        }
    }

    /// Pre-generate thumbnails and extract color after import
    private func postImportProcess(_ wallpaper: Wallpaper) {
        Task {
            // Pre-generate both common thumbnail sizes
            _ = await wallpaper.generateThumbnail(size: CGSize(width: 320, height: 180))
            _ = await wallpaper.generateThumbnail(size: CGSize(width: 160, height: 90))

            // Extract dominant color
            if let hex = await wallpaper.extractDominantColor() {
                await MainActor.run {
                    if let idx = wallpapers.firstIndex(where: { $0.id == wallpaper.id }) {
                        wallpapers[idx].dominantColorHex = hex
                        var colors = savedColors
                        colors[wallpaper.url.path] = hex
                        savedColors = colors
                    }
                }
            }
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

    /// Renames a wallpaper (sets custom display title)
    func renameWallpaper(_ wallpaper: Wallpaper, to newTitle: String) {
        if let index = wallpapers.firstIndex(where: { $0.id == wallpaper.id }) {
            let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            wallpapers[index].customTitle = trimmed.isEmpty ? nil : trimmed
            saveCustomTitles()

            // Update widget if this is the current wallpaper
            if currentWallpaper?.id == wallpaper.id {
                currentWallpaper = wallpapers[index]
                Task { await syncCurrentWallpaperToWidget() }
            }
        }
    }

    /// Toggles favorite status for a wallpaper
    func toggleFavorite(_ wallpaper: Wallpaper) {
        if let index = wallpapers.firstIndex(where: { $0.id == wallpaper.id }) {
            wallpapers[index].isFavorite.toggle()

            // Keep currentWallpaper in sync
            if currentWallpaper?.id == wallpaper.id {
                currentWallpaper = wallpapers[index]
            }

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

    // MARK: - Custom Titles Persistence

    /// Path → custom title mapping
    private var customTitles: [String: String] {
        get {
            guard !customWallpaperTitlesData.isEmpty,
                  let data = customWallpaperTitlesData.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([String: String].self, from: data)
            else { return [:] }
            return dict
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let str = String(data: data, encoding: .utf8) {
                customWallpaperTitlesData = str
            }
        }
    }

    /// Saves custom titles to UserDefaults
    private func saveCustomTitles() {
        var titles: [String: String] = [:]
        for wp in wallpapers where wp.customTitle != nil {
            titles[wp.url.path] = wp.customTitle
        }
        customTitles = titles
    }

    /// Applies saved custom titles after loading wallpapers
    private func applyCustomTitles() {
        let titles = customTitles
        guard !titles.isEmpty else { return }
        for i in wallpapers.indices {
            if let title = titles[wallpapers[i].url.path] {
                wallpapers[i].customTitle = title
            }
        }
    }

    // MARK: - Dominant Color Persistence

    private var savedColors: [String: String] {
        get {
            guard !wallpaperColorsData.isEmpty,
                  let data = wallpaperColorsData.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([String: String].self, from: data)
            else { return [:] }
            return dict
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let str = String(data: data, encoding: .utf8) {
                wallpaperColorsData = str
            }
        }
    }

    private func applySavedColors() {
        let colors = savedColors
        guard !colors.isEmpty else { return }
        for i in wallpapers.indices {
            if let hex = colors[wallpapers[i].url.path] {
                wallpapers[i].dominantColorHex = hex
            }
        }
    }

    /// Extract colors for wallpapers that don't have one yet
    func extractMissingColors() {
        Task {
            var updatedColors = savedColors
            for i in wallpapers.indices where wallpapers[i].dominantColorHex == nil {
                if let hex = await wallpapers[i].extractDominantColor() {
                    await MainActor.run {
                        wallpapers[i].dominantColorHex = hex
                    }
                    updatedColors[wallpapers[i].url.path] = hex
                }
            }
            await MainActor.run {
                savedColors = updatedColors
            }
        }
    }

    // MARK: - Tags

    private var savedTags: [String: [String]] {
        get {
            guard !wallpaperTagsData.isEmpty,
                  let data = wallpaperTagsData.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([String: [String]].self, from: data)
            else { return [:] }
            return dict
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let str = String(data: data, encoding: .utf8) {
                wallpaperTagsData = str
            }
        }
    }

    private func applySavedTags() {
        let tags = savedTags
        guard !tags.isEmpty else { return }
        for i in wallpapers.indices {
            if let t = tags[wallpapers[i].url.path] {
                wallpapers[i].tags = t
            }
        }
    }

    /// Add a tag to a wallpaper
    func addTag(_ tag: String, to wallpaper: Wallpaper) {
        guard let index = wallpapers.firstIndex(where: { $0.id == wallpaper.id }) else { return }
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !wallpapers[index].tags.contains(trimmed) else { return }
        wallpapers[index].tags.append(trimmed)
        var all = savedTags
        all[wallpapers[index].url.path] = wallpapers[index].tags
        savedTags = all
    }

    /// Remove a tag from a wallpaper
    func removeTag(_ tag: String, from wallpaper: Wallpaper) {
        guard let index = wallpapers.firstIndex(where: { $0.id == wallpaper.id }) else { return }
        wallpapers[index].tags.removeAll { $0 == tag }
        var all = savedTags
        all[wallpapers[index].url.path] = wallpapers[index].tags
        savedTags = all
    }

    /// All unique tags across library
    var allTags: [String] {
        Array(Set(wallpapers.flatMap { $0.tags })).sorted()
    }

    // MARK: - Fuzzy Search

    /// Search wallpapers by name, tags, and fuzzy matching
    func searchWallpapers(query: String) -> [Wallpaper] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return wallpapers }

        return wallpapers
            .map { wp -> (Wallpaper, Int) in
                var score = 0
                let name = wp.displayName.lowercased()

                // Exact match
                if name == q { score += 100 }
                // Contains
                else if name.contains(q) { score += 70 }
                // Tag match
                if wp.tags.contains(q) { score += 80 }
                if wp.tags.contains(where: { $0.contains(q) }) { score += 50 }
                // Fuzzy: characters appear in order
                if score == 0 { score = fuzzyScore(query: q, in: name) }

                return (wp, score)
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    private func fuzzyScore(query: String, in text: String) -> Int {
        var qi = query.startIndex
        var ti = text.startIndex
        var matched = 0

        while qi < query.endIndex && ti < text.endIndex {
            if query[qi] == text[ti] {
                matched += 1
                qi = query.index(after: qi)
            }
            ti = text.index(after: ti)
        }

        // All chars matched in order → score based on match ratio
        return qi == query.endIndex ? max(10, matched * 30 / query.count) : 0
    }

    // MARK: - File Watching

    private func startFileWatching() {
        let fd = open(libraryURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            NSLog("[WallpaperManager] Library folder changed — reloading")
            self?.loadWallpapers()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        fileWatcher = source
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

    /// All formats supported for import (including those that need conversion)
    static let supportedImportExtensions = VideoFormatConverter.allSupportedFormats

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
    static let openMainWindow = Notification.Name("openMainWindow")
}

// MARK: - Screen Wallpaper Info

/// Information about a per-screen wallpaper change
struct ScreenWallpaperInfo {
    let wallpaper: Wallpaper
    let screen: NSScreen
}
