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

/// Serial gate for the import critical section (KRITIK-2). An actor's
/// reentrancy semantics guarantee that only one call runs through the
/// closure at a time across all concurrent importers.
actor ImportGate {
    func run<T: Sendable>(_ block: @Sendable () async throws -> T) async rethrows -> T {
        try await block()
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

    @Published var wallpapers: [Wallpaper] = [] {
        didSet {
            // P1-4 / KRITIK-1: only rebuild when the structural shape
            // changes (length or ordering). Subscript mutations like
            // `wallpapers[i].isFavorite.toggle()` ALSO fire didSet (Array
            // is value-type, subscript = mutation). Without this guard we
            // pay an O(n) Dictionary rebuild on every toggle — defeating
            // the O(1) lookup the indexById exists to provide.
            if oldValue.count != wallpapers.count
                || !oldValue.elementsEqual(wallpapers, by: { $0.id == $1.id })
            {
                rebuildIndex()
            }
        }
    }
    @Published var currentWallpaper: Wallpaper?
    @Published var isPlaying: Bool = false
    @Published var wallpaperMode: WallpaperMode = .same

    /// Maps wallpaper.id → index in `wallpapers`. Rebuilt on every
    /// mutation via didSet; cost is one O(n) pass amortised over many
    /// O(1) lookups.
    private var indexById: [UUID: Int] = [:]

    private func rebuildIndex() {
        indexById = Dictionary(uniqueKeysWithValues: wallpapers.enumerated().map { ($0.element.id, $0.offset) })
    }

    /// O(1) index lookup. Returns nil if id is unknown.
    private func index(of id: UUID) -> Int? {
        if let i = indexById[id], i < wallpapers.count, wallpapers[i].id == id {
            return i
        }
        // Defensive fallback (e.g. mid-mutation race) — rebuild and retry.
        rebuildIndex()
        return indexById[id]
    }

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
    private let cache = WallpaperMetadataCache.shared

    // P1-6: persistence debouncers. Toggling favorites rapidly used to
    // re-encode the entire favorites JSON per click. We now coalesce
    // bursts into a single write 250ms after the last mutation.
    private var pendingFavoritesWrite: DispatchWorkItem?
    private var pendingTitlesWrite: DispatchWorkItem?
    private var pendingTagsWrite: DispatchWorkItem?

    private func scheduleFavoritesWrite() {
        pendingFavoritesWrite?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.metadata.saveFavorites(from: self.wallpapers)
        }
        pendingFavoritesWrite = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    private func scheduleTitlesWrite() {
        pendingTitlesWrite?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.metadata.saveCustomTitles(from: self.wallpapers)
        }
        pendingTitlesWrite = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    private func scheduleTagsWrite() {
        pendingTagsWrite?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            var all: [String: [String]] = [:]
            for wp in self.wallpapers { all[wp.url.path] = wp.tags }
            self.metadata.savedTags = all
        }
        pendingTagsWrite = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

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
            do {
                screenWallpapers = try JSONDecoder().decode([String: UUID].self, from: screenWallpapersData)
            } catch {
                Log.app.error("Failed to decode per-screen wallpaper map; resetting. \(String(describing: error), privacy: .public)")
                screenWallpapersData = Data()
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
        do {
            screenWallpapersData = try JSONEncoder().encode(screenWallpapers)
        } catch {
            Log.app.error("Failed to persist per-screen wallpaper map: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Library Management

    func loadWallpapers() {
        let favPaths = metadata.favoritePaths
        wallpapers = library.loadAll(favoritePaths: favPaths)

        metadata.applyCustomTitles(to: &wallpapers)
        metadata.applySavedColors(to: &wallpapers)
        metadata.applySavedTags(to: &wallpapers)

        cache.replaceAll(with: wallpapers)

        loadMetadataInBackground()
        extractMissingColors()
    }

    func isDuplicate(of sourceURL: URL) -> Wallpaper? {
        let sourceSize = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path))?[.size] as? Int64 ?? 0
        let sourceName = sourceURL.deletingPathExtension().lastPathComponent
        return wallpapers.first { $0.fileSize == sourceSize && $0.name == sourceName }
    }

    /// KRITIK-2: serializes the (duplicate-check + file-import + array-
    /// append) critical section so concurrent callers (e.g. drag-drop of
    /// the same file twice, or `importVideos` running in parallel) can't
    /// both pass duplicate-check on a stale snapshot and end up with two
    /// records of the same source.
    private let importGate = ImportGate()

    func importVideo(from sourceURL: URL) async throws -> Wallpaper {
        // Serialize the critical region. `postImportProcess` runs after
        // the gate releases so thumbnails/color extraction stay parallel.
        let wallpaper = try await importGate.run { [weak self] in
            guard let self else { throw CancellationError() }
            let destURL = try await self.library.importFile(
                from: sourceURL,
                existingWallpapers: self.wallpapers
            )
            let wp = Wallpaper(url: destURL)
            await MainActor.run {
                self.wallpapers.append(wp)
            }
            return wp
        }
        postImportProcess(wallpaper)
        return wallpaper
    }

    /// P3-12 / YUKSEK-1: true producer-consumer. Maintains up to
    /// `maxInflight` tasks in flight at any moment; as each finishes a
    /// new one is added until the input is exhausted. KRITIK-2's gate
    /// serializes the actual duplicate-check + file-move + append step
    /// inside each `importVideo` call, so this concurrency is safe.
    func importVideos(from sourceURLs: [URL], maxInflight: Int = 4) async -> [Result<Wallpaper, Error>] {
        await withTaskGroup(of: (Int, Result<Wallpaper, Error>).self, returning: [Result<Wallpaper, Error>].self) { group in
            var nextIndex = 0
            var inflight = 0
            var collected: [(Int, Result<Wallpaper, Error>)] = []

            func dispatch(_ i: Int) {
                let url = sourceURLs[i]
                group.addTask { [weak self] in
                    guard let self else { return (i, .failure(CancellationError())) }
                    do {
                        return (i, .success(try await self.importVideo(from: url)))
                    } catch {
                        return (i, .failure(error))
                    }
                }
                inflight += 1
                nextIndex += 1
            }

            // Prime — fill the in-flight window.
            while nextIndex < sourceURLs.count && inflight < maxInflight {
                dispatch(nextIndex)
            }

            // Drain + refill: as each task completes, immediately
            // dispatch the next pending URL.
            while let result = await group.next() {
                collected.append(result)
                inflight -= 1
                if nextIndex < sourceURLs.count {
                    dispatch(nextIndex)
                }
            }

            return collected.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    private func postImportProcess(_ wallpaper: Wallpaper) {
        cache.upsert(wallpaper)
        Task {
            _ = await wallpaper.generateThumbnail(size: CGSize(width: 320, height: 180))
            _ = await wallpaper.generateThumbnail(size: CGSize(width: 160, height: 90))

            if let hex = await wallpaper.extractDominantColor() {
                await MainActor.run {
                    if let idx = index(of: wallpaper.id) {
                        wallpapers[idx].dominantColorHex = hex
                        var colors = metadata.savedColors
                        colors[wallpaper.url.path] = hex
                        metadata.savedColors = colors
                        cache.upsert(wallpapers[idx])
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
        scheduleFavoritesWrite()
        cache.delete(id: wallpaper.id)
        Task { await widgetSync.syncFavorites(wallpapers.filter { $0.isFavorite }) }
    }

    func renameWallpaper(_ wallpaper: Wallpaper, to newTitle: String) {
        if let index = index(of: wallpaper.id) {
            let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            wallpapers[index].customTitle = trimmed.isEmpty ? nil : trimmed
            scheduleTitlesWrite()
            cache.upsert(wallpapers[index])
            if currentWallpaper?.id == wallpaper.id {
                currentWallpaper = wallpapers[index]
                Task { await widgetSync.syncCurrentWallpaper(currentWallpaper) }
            }
        }
    }

    func toggleFavorite(_ wallpaper: Wallpaper) {
        if let index = index(of: wallpaper.id) {
            wallpapers[index].isFavorite.toggle()
            if currentWallpaper?.id == wallpaper.id {
                currentWallpaper = wallpapers[index]
            }
            scheduleFavoritesWrite()
            cache.upsert(wallpapers[index])
            Task { await widgetSync.syncFavorites(wallpapers.filter { $0.isFavorite }) }
        }
    }

    // MARK: - Tags

    func addTag(_ tag: String, to wallpaper: Wallpaper) {
        guard let index = index(of: wallpaper.id) else { return }
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !wallpapers[index].tags.contains(trimmed) else { return }
        wallpapers[index].tags.append(trimmed)
        scheduleTagsWrite()
        cache.upsert(wallpapers[index])
    }

    func removeTag(_ tag: String, from wallpaper: Wallpaper) {
        guard let index = index(of: wallpaper.id) else { return }
        wallpapers[index].tags.removeAll { $0 == tag }
        scheduleTagsWrite()
        cache.upsert(wallpapers[index])
    }

    var allTags: [String] {
        Array(Set(wallpapers.flatMap { $0.tags })).sorted()
    }

    // MARK: - Fuzzy Search

    func searchWallpapers(query: String) -> [Wallpaper] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return wallpapers }

        // P3-11: small libraries hit the in-memory path; large libraries
        // (>200) route through SQLite where indexes on name/tags pay off.
        // Falls back to in-memory if the cache returns empty (e.g. cache
        // not yet rebuilt at first launch).
        if wallpapers.count > 200, let cached = sqlSearch(q: q), !cached.isEmpty {
            return cached
        }

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

    private func sqlSearch(q: String) -> [Wallpaper]? {
        let ids = cache.searchIds(query: q)
        guard !ids.isEmpty else { return nil }
        return ids.compactMap { id in
            guard let i = indexById[id], i < wallpapers.count else { return nil }
            return wallpapers[i]
        }
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
           let idx = index(of: current.id) {
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
           let currentIndex = index(of: current.id) {
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
