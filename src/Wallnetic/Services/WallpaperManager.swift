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

/// Receives playback commands directly instead of through NotificationCenter.
protocol PlaybackDelegate: AnyObject {
    func playbackSetWallpaper(url: URL)
    func playbackSetWallpaper(url: URL, for screen: NSScreen)
    func playbackPlay()
    func playbackPause()
    func playbackApplyScreenWallpapers()
}

/// Central coordinator for wallpaper state and settings.
/// Delegates file I/O to WallpaperLibrary, metadata to WallpaperMetadataStore,
/// and widget sync to WidgetSyncService.
class WallpaperManager: ObservableObject {
    static let shared = WallpaperManager()

    // MARK: - Published Properties

    @Published var wallpapers: [Wallpaper] = []
    @Published var currentWallpaper: Wallpaper?
    @Published var isPlaying: Bool = false
    @Published var wallpaperMode: WallpaperMode = .same

    /// Per-screen wallpaper assignments (screenName -> wallpaperID)
    @Published var screenWallpapers: [String: UUID] = [:]

    // MARK: - Settings

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

    // MARK: - Delegates & Services

    /// Set by AppDelegate to receive direct playback commands (#170).
    weak var playbackDelegate: PlaybackDelegate?

    private let library = WallpaperLibrary.shared
    private let metadata = WallpaperMetadataStore.shared
    private let widgetSync = WidgetSyncService.shared

    // MARK: - Initialization

    private init() {
        loadWallpapers()
        loadSettings()
        syncToWidget()
        library.startWatching { [weak self] in
            self?.loadWallpapers()
        }
    }

    private func loadSettings() {
        if let mode = WallpaperMode(rawValue: wallpaperModeRaw) {
            wallpaperMode = mode
        }

        if !screenWallpapersData.isEmpty {
            if let decoded = try? JSONDecoder().decode([String: UUID].self, from: screenWallpapersData) {
                screenWallpapers = decoded
            }
        }

        if !lastWallpaperURL.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.restoreLastWallpaper()
            }
        }
    }

    private func restoreLastWallpaper() {
        guard !lastWallpaperURL.isEmpty else { return }
        let url = URL(fileURLWithPath: lastWallpaperURL)
        if let wallpaper = wallpapers.first(where: { $0.url.path == url.path }) {
            setWallpaper(wallpaper)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.isPlaying = true
                self?.playbackDelegate?.playbackPlay()
                // Keep notification for broadcast consumers (widget, etc.)
                NotificationCenter.default.post(name: .playbackStateDidChange, object: true)
            }
        }
    }

    private func saveScreenWallpapers() {
        if let encoded = try? JSONEncoder().encode(screenWallpapers) {
            screenWallpapersData = encoded
        }
    }

    // MARK: - Library Management

    func loadWallpapers() {
        let favPaths = metadata.favoritePaths
        wallpapers = library.loadAll(favoritePaths: favPaths)

        metadata.applyCustomTitles(to: &wallpapers)
        metadata.applySavedColors(to: &wallpapers)
        metadata.applySavedTags(to: &wallpapers)

        loadMetadataInBackground()
        extractMissingColors()
    }

    func isDuplicate(of sourceURL: URL) -> Wallpaper? {
        let sourceSize = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path))?[.size] as? Int64 ?? 0
        let sourceName = sourceURL.deletingPathExtension().lastPathComponent
        return wallpapers.first { $0.fileSize == sourceSize && $0.name == sourceName }
    }

    func importVideo(from sourceURL: URL) async throws -> Wallpaper {
        let destURL = try await library.importFile(from: sourceURL, existingWallpapers: wallpapers)
        let wallpaper = Wallpaper(url: destURL)
        await MainActor.run {
            wallpapers.append(wallpaper)
        }
        postImportProcess(wallpaper)
        return wallpaper
    }

    private func postImportProcess(_ wallpaper: Wallpaper) {
        Task {
            _ = await wallpaper.generateThumbnail(size: CGSize(width: 320, height: 180))
            _ = await wallpaper.generateThumbnail(size: CGSize(width: 160, height: 90))

            if let hex = await wallpaper.extractDominantColor() {
                await MainActor.run {
                    if let idx = wallpapers.firstIndex(where: { $0.id == wallpaper.id }) {
                        wallpapers[idx].dominantColorHex = hex
                        var colors = metadata.savedColors
                        colors[wallpaper.url.path] = hex
                        metadata.savedColors = colors
                    }
                }
            }
        }
    }

    func removeWallpaper(_ wallpaper: Wallpaper) {
        library.removeFile(at: wallpaper.url)
        wallpapers.removeAll { $0.id == wallpaper.id }
        if currentWallpaper?.id == wallpaper.id {
            currentWallpaper = nil
        }
        metadata.saveFavorites(from: wallpapers)
        Task { await widgetSync.syncFavorites(wallpapers.filter { $0.isFavorite }) }
    }

    func renameWallpaper(_ wallpaper: Wallpaper, to newTitle: String) {
        if let index = wallpapers.firstIndex(where: { $0.id == wallpaper.id }) {
            let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            wallpapers[index].customTitle = trimmed.isEmpty ? nil : trimmed
            metadata.saveCustomTitles(from: wallpapers)
            if currentWallpaper?.id == wallpaper.id {
                currentWallpaper = wallpapers[index]
                Task { await widgetSync.syncCurrentWallpaper(currentWallpaper) }
            }
        }
    }

    func toggleFavorite(_ wallpaper: Wallpaper) {
        if let index = wallpapers.firstIndex(where: { $0.id == wallpaper.id }) {
            wallpapers[index].isFavorite.toggle()
            if currentWallpaper?.id == wallpaper.id {
                currentWallpaper = wallpapers[index]
            }
            metadata.saveFavorites(from: wallpapers)
            Task { await widgetSync.syncFavorites(wallpapers.filter { $0.isFavorite }) }
        }
    }

    // MARK: - Tags

    func addTag(_ tag: String, to wallpaper: Wallpaper) {
        guard let index = wallpapers.firstIndex(where: { $0.id == wallpaper.id }) else { return }
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !wallpapers[index].tags.contains(trimmed) else { return }
        wallpapers[index].tags.append(trimmed)
        var all = metadata.savedTags
        all[wallpapers[index].url.path] = wallpapers[index].tags
        metadata.savedTags = all
    }

    func removeTag(_ tag: String, from wallpaper: Wallpaper) {
        guard let index = wallpapers.firstIndex(where: { $0.id == wallpaper.id }) else { return }
        wallpapers[index].tags.removeAll { $0 == tag }
        var all = metadata.savedTags
        all[wallpapers[index].url.path] = wallpapers[index].tags
        metadata.savedTags = all
    }

    var allTags: [String] {
        Array(Set(wallpapers.flatMap { $0.tags })).sorted()
    }

    // MARK: - Fuzzy Search

    func searchWallpapers(query: String) -> [Wallpaper] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return wallpapers }

        return wallpapers
            .map { wp -> (Wallpaper, Int) in
                var score = 0
                let name = wp.displayName.lowercased()
                if name == q { score += 100 }
                else if name.contains(q) { score += 70 }
                if wp.tags.contains(q) { score += 80 }
                if wp.tags.contains(where: { $0.contains(q) }) { score += 50 }
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
        return qi == query.endIndex ? max(10, matched * 30 / query.count) : 0
    }

    // MARK: - Async Metadata

    private func loadMetadataInBackground() {
        Task {
            for i in wallpapers.indices {
                var wp = wallpapers[i]
                if wp.duration == nil {
                    await wp.loadMetadata()
                    await MainActor.run {
                        if i < wallpapers.count && wallpapers[i].id == wp.id {
                            wallpapers[i].duration = wp.duration
                            wallpapers[i].resolution = wp.resolution
                        }
                    }
                }
            }
        }
    }

    func extractMissingColors() {
        Task {
            var updatedColors = metadata.savedColors
            for i in wallpapers.indices where wallpapers[i].dominantColorHex == nil {
                if let hex = await wallpapers[i].extractDominantColor() {
                    await MainActor.run {
                        wallpapers[i].dominantColorHex = hex
                    }
                    updatedColors[wallpapers[i].url.path] = hex
                }
            }
            await MainActor.run {
                metadata.savedColors = updatedColors
            }
        }
    }

    // MARK: - Playback

    /// Sets wallpaper for all screens (same mode).
    /// PlaybackDelegate drives the renderer directly (#170); the broadcast
    /// notification fans out to observers like DynamicIslandController and
    /// ThemeManager that react to wallpaper changes.
    func setWallpaper(_ wallpaper: Wallpaper) {
        currentWallpaper = wallpaper
        lastWallpaperURL = wallpaper.url.path
        isPlaying = true

        playbackDelegate?.playbackSetWallpaper(url: wallpaper.url)
        playbackDelegate?.playbackPlay()

        NotificationCenter.default.post(name: .wallpaperDidChange, object: wallpaper)
        NotificationCenter.default.post(name: .playbackStateDidChange, object: true)

        Task {
            await widgetSync.syncCurrentWallpaper(wallpaper)
            widgetSync.syncPlaybackState(isPlaying: true)
        }
    }

    /// Sets wallpaper for a specific screen (different mode).
    func setWallpaper(_ wallpaper: Wallpaper, for screen: NSScreen) {
        let screenName = screen.localizedName
        screenWallpapers[screenName] = wallpaper.id
        saveScreenWallpapers()
        isPlaying = true

        playbackDelegate?.playbackSetWallpaper(url: wallpaper.url, for: screen)
        playbackDelegate?.playbackPlay()

        NotificationCenter.default.post(
            name: .screenWallpaperDidChange,
            object: ScreenWallpaperInfo(wallpaper: wallpaper, screen: screen)
        )
        NotificationCenter.default.post(name: .playbackStateDidChange, object: true)
    }

    func wallpaper(for screen: NSScreen) -> Wallpaper? {
        guard let wallpaperID = screenWallpapers[screen.localizedName] else {
            return currentWallpaper
        }
        return wallpapers.first { $0.id == wallpaperID }
    }

    func setWallpaperMode(_ mode: WallpaperMode) {
        wallpaperMode = mode
        wallpaperModeRaw = mode.rawValue

        if mode == .same, let wallpaper = currentWallpaper {
            playbackDelegate?.playbackSetWallpaper(url: wallpaper.url)
            NotificationCenter.default.post(name: .wallpaperDidChange, object: wallpaper)
        } else if mode == .different {
            playbackDelegate?.playbackApplyScreenWallpapers()
            NotificationCenter.default.post(name: .applyScreenWallpapers, object: nil)
        }
    }

    func togglePlayback() {
        isPlaying.toggle()

        if isPlaying {
            playbackDelegate?.playbackPlay()
        } else {
            playbackDelegate?.playbackPause()
        }
        NotificationCenter.default.post(name: .playbackStateDidChange, object: isPlaying)

        widgetSync.syncPlaybackState(isPlaying: isPlaying)
    }

    // MARK: - Navigation

    func cycleToPreviousWallpaper() {
        guard !wallpapers.isEmpty else { return }
        if let current = currentWallpaper,
           let idx = wallpapers.firstIndex(where: { $0.id == current.id }) {
            let prevIdx = (idx - 1 + wallpapers.count) % wallpapers.count
            setWallpaper(wallpapers[prevIdx])
        } else if let last = wallpapers.last {
            setWallpaper(last)
        }
    }

    func setRandomWallpaper() {
        let candidates = wallpapers.filter { $0.id != currentWallpaper?.id }
        guard let random = candidates.randomElement() else { return }
        setWallpaper(random)
    }

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

    // MARK: - Helpers

    static let supportedImportExtensions = VideoFormatConverter.allSupportedFormats

    // MARK: - Widget

    func syncToWidget() {
        guard currentWallpaper != nil else { return }
        widgetSync.syncAll(current: currentWallpaper, isPlaying: isPlaying, wallpapers: wallpapers)
    }

    /// Handles URL scheme from widget
    func handleWidgetURL(_ url: URL) {
        guard let (action, wallpaperID) = SharedDataManager.parseWidgetURL(url) else { return }

        switch action {
        case .playPause:
            togglePlayback()
        case .setWallpaper:
            if let id = wallpaperID,
               let wallpaper = wallpapers.first(where: { $0.id == id }) {
                setWallpaper(wallpaper)
            }
        case .nextWallpaper:
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

struct ScreenWallpaperInfo {
    let wallpaper: Wallpaper
    let screen: NSScreen
}
