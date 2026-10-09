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
    case unsupportedFile

    var errorDescription: String? {
        switch self {
        case .duplicate(let name):
            return "'\(name)' is already in your library"
        case .unsupportedFile:
            return "Choose a video or animated image in MP4, MOV, M4V, HEVC, GIF, WebM, or WebP format."
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

/// Holds an explicit permit across suspension points: actor isolation alone
/// allows another import to enter whenever the current import awaits conversion.
actor ImportGate {
    private var isRunning = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(_ block: @Sendable () async throws -> T) async throws -> T {
        if isRunning {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            isRunning = true
        }
        defer {
            if waiters.isEmpty {
                isRunning = false
            } else {
                waiters.removeFirst().resume()
            }
        }
        try Task.checkCancellation()
        return try await block()
    }
}

/// Receives playback commands directly instead of through NotificationCenter.
protocol PlaybackDelegate: AnyObject {
    var playbackIsPlaying: Bool { get }
    func playbackSetWallpaper(url: URL)
    func playbackSetWallpaper(url: URL, for screen: NSScreen)
    /// - Returns: whether playback actually started. A power condition (screen
    ///   asleep, locked, on battery, fullscreen app) swallows the request, and
    ///   callers must not report "Playing" over a desktop that isn't.
    @discardableResult func playbackPlay() -> Bool
    func playbackPause()
    func playbackRetry(on displayID: UInt32)
    func playbackClearWallpaper(url: URL)
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
    @Published var isPausedAfterDuration: Bool = false
    @Published var displayPlaybackStatuses: [DisplayPlaybackStatus] = []

    func retryWallpaper(on displayID: UInt32) {
        playbackDelegate?.playbackRetry(on: displayID)
    }
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
    private let displayAssignments = DisplayWallpaperAssignments()

    // MARK: - Settings

    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("pauseOnBattery") var pauseOnBattery: Bool = true
    @AppStorage("pauseOnFullscreen") var pauseOnFullscreen: Bool = true
    @AppStorage("shouldAutoResume") var shouldAutoResume: Bool = true
    @AppStorage("wallpaperModeRaw") private var wallpaperModeRaw: String = "same"
    @AppStorage("screenWallpapersData") private var screenWallpapersData: Data = Data()
    @AppStorage("useMetalRenderer") var useMetalRenderer: Bool = true
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
    private var isRemovingStorage = false

    private lazy var storage = LibraryStorage(
        libraryURL: library.libraryURL,
        framesURL: SystemWallpaperSync.framesDirectory(),
        thumbnailsURL: SharedDataManager.shared.thumbnailsDirectory,
        metadataURL: applicationSupportURL().appendingPathComponent("Wallnetic/metadata.sqlite"))

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

        if !lastWallpaperURL.isEmpty || displayAssignments.hasAssignments {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.restoreLastWallpaper()
            }
        }
    }

    private func restoreLastWallpaper() {
        if wallpaperMode == .different, displayAssignments.hasAssignments {
            for screen in NSScreen.screens {
                if let wallpaper = wallpaper(for: screen) {
                    setWallpaper(wallpaper, for: screen, userInitiated: false)
                }
            }
            return
        }
        guard !lastWallpaperURL.isEmpty else { return }
        let url = URL(fileURLWithPath: lastWallpaperURL)
        if let wallpaper = wallpapers.first(where: { $0.url.path == url.path }) {
            // Launch restore is not a deliberate apply — it must not count
            // toward the rating prompt.
            setWallpaper(wallpaper, userInitiated: false)
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
        guard !isRemovingStorage else { return }
        let favPaths = metadata.favoritePaths
        let ids = Dictionary(wallpapers.map { ($0.url.path, $0.id) }, uniquingKeysWith: { first, _ in first })
        wallpapers = library.loadAll(favoritePaths: favPaths, existingIDs: ids)

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
            let existingWallpapers = await MainActor.run { self.wallpapers }
            let destURL = try await self.library.importFile(
                from: sourceURL,
                existingWallpapers: existingWallpapers
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
        let concurrencyLimit = max(1, maxInflight)
        return await withTaskGroup(of: (Int, Result<Wallpaper, Error>).self, returning: [Result<Wallpaper, Error>].self) { group in
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
            while nextIndex < sourceURLs.count && inflight < concurrencyLimit {
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
        Task { @MainActor in
            do {
                let scan = try await scanStorage()
                guard let item = scan.items.first(where: { $0.url.path == wallpaper.url.path && $0.canRemove }) else {
                    throw StorageError.unsafeFile
                }
                let alert = NSAlert()
                alert.messageText = "Remove this library copy?"
                alert.informativeText = "\(wallpaper.displayName) (\(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))). This permanently removes the app-managed copy and its assignments. Your original source file is kept."
                alert.addButton(withTitle: "Remove")
                alert.addButton(withTitle: "Cancel")
                alert.buttons.first?.hasDestructiveAction = true
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                let result = await removeStorageItems([item])
                if !result.failures.isEmpty {
                    let failure = NSAlert()
                    failure.messageText = "Could not remove the copy"
                    failure.informativeText = result.failures.joined(separator: "\n")
                    failure.runModal()
                }
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }

    @MainActor
    private var protectedThumbnailNames: Set<String> {
        Set(wallpapers.map { $0.id.uuidString + ".jpg" })
    }

    private static func storedThumbnailNames() throws -> Set<String> {
        let shared = try SharedDataManager.shared.readSharedDataForStorage()
        var names = Set<String>()
        names.formUnion(shared.favorites.compactMap(\.thumbnailPath))
        if let current = shared.currentThumbnailPath { names.insert(current) }
        return names
    }

    @MainActor
    func scanStorage() async throws -> StorageScan {
        let service = storage
        let protected = protectedThumbnailNames
        let task = Task.detached(priority: .utility) {
            var names = protected
            var failure: String?
            if service.thumbnailsURL != nil {
                do { names.formUnion(try Self.storedThumbnailNames()) }
                catch { failure = "Widget references could not be read; cache cleanup is unavailable. \(error.localizedDescription)" }
            }
            var scan = try service.scan(protectedThumbnailNames: names)
            if let failure {
                scan.failures.append(failure)
                for index in scan.items.indices where scan.items[index].category == .caches {
                    scan.items[index].canRemove = false
                }
            }
            return scan
        }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }

    @MainActor
    func removeStorageItems(_ items: [StorageItem]) async -> StorageRemovalResult {
        do {
            return try await importGate.run { [self] in
                let (service, protected) = await MainActor.run {
                    self.isRemovingStorage = true
                    return (self.storage, self.protectedThumbnailNames)
                }
                let result = await Task.detached(priority: .utility) {
                    var names = protected
                    if items.contains(where: { $0.category == .caches }) {
                        do { names.formUnion(try Self.storedThumbnailNames()) }
                        catch {
                            var result = service.remove(items.filter { $0.category == .videos })
                            result.failures.append("Cache cleanup skipped: widget references could not be read. \(error.localizedDescription)")
                            return result
                        }
                    }
                    return service.remove(items, protectedThumbnailNames: names)
                }.value
                await MainActor.run {
                    self.finishStorageRemoval(result)
                    self.isRemovingStorage = false
                    self.loadWallpapers()
                }
                return result
            }
        } catch {
            return StorageRemovalResult(failures: [error.localizedDescription])
        }
    }

    @MainActor
    private func finishStorageRemoval(_ result: StorageRemovalResult) {
        let update = LibraryRemovalState(result: result, wallpapers: wallpapers, current: currentWallpaper,
                                         screenAssignments: screenWallpapers)
        let urls = update.urls
        guard !urls.isEmpty else { return }
        let paths = update.paths
        for url in urls {
            playbackDelegate?.playbackClearWallpaper(url: url)
            displayAssignments.remove(url)
        }
        screenWallpapers = update.screenAssignments
        saveScreenWallpapers()
        if paths.contains(lastWallpaperURL) { lastWallpaperURL = "" }
        currentWallpaper = update.current
        wallpapers = update.wallpapers
        isPlaying = playbackDelegate?.playbackIsPlaying ?? false

        // Clear persisted automation references in the same main-actor turn.
        OptimizedCopyStore.shared.removeCopies(at: paths)
        CollectionManager.shared.removeWallpaperIDs(update.ids)
        TimeOfDayManager.shared.removeWallpaperPaths(paths)
        PlaylistManager.shared.removeWallpaperPaths(paths)
        WeatherWallpaperManager.shared.removeWallpaperPaths(paths)
        SpaceWallpaperManager.shared.removeWallpaperPaths(paths)
        pendingFavoritesWrite?.cancel()
        pendingTitlesWrite?.cancel()
        pendingTagsWrite?.cancel()
        metadata.favoritePaths.subtract(paths)
        metadata.customTitles = metadata.customTitles.filter { !paths.contains($0.key) }
        metadata.savedTags = metadata.savedTags.filter { !paths.contains($0.key) }
        metadata.savedColors = metadata.savedColors.filter { !paths.contains($0.key) }
        cache.replaceAll(with: wallpapers)
        ThumbnailCache.shared.clearCache()
        NotificationCenter.default.post(name: .playbackStateDidChange, object: isPlaying)
        widgetSync.syncAll(current: currentWallpaper, isPlaying: isPlaying, wallpapers: wallpapers)
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
        Task { @MainActor in
            let targets = wallpapers
            for var wp in targets {
                if wp.duration == nil {
                    await wp.loadMetadata()
                    // Immutable copies — capturing the mutated `var wp` in the
                    // @MainActor closure is a compile error under Release/WMO
                    // (Xcode 15.2 Intel job: "reference to captured var 'wp'
                    // in concurrently-executing code").
                    let id = wp.id
                    let duration = wp.duration
                    let resolution = wp.resolution
                    await MainActor.run {
                        if let i = index(of: id) {
                            wallpapers[i].duration = duration
                            wallpapers[i].resolution = resolution
                        }
                    }
                }
            }
        }
    }

    func extractMissingColors() {
        Task { @MainActor in
            // Snapshot the wallpapers needing color extraction by their id;
            // after each suspension we re-resolve the index via id so the
            // write goes to the right wallpaper (or no-op if it was deleted
            // during the async gap).
            let targets: [(id: UUID, url: URL)] = wallpapers
                .filter { $0.dominantColorHex == nil }
                .map { ($0.id, $0.url) }
            var updatedColors = metadata.savedColors
            for target in targets {
                guard let snapshot = wallpapers.first(where: { $0.id == target.id }) else { continue }
                if let hex = await snapshot.extractDominantColor() {
                    await MainActor.run {
                        if let idx = wallpapers.firstIndex(where: { $0.id == target.id }) {
                            wallpapers[idx].dominantColorHex = hex
                        }
                    }
                    updatedColors[target.url.path] = hex
                }
            }
            // Immutable copy — same captured-var-in-concurrent-code fix as above.
            let colors = updatedColors
            await MainActor.run {
                let existingPaths = Set(wallpapers.map { $0.url.path })
                metadata.savedColors = colors.filter { existingPaths.contains($0.key) }
            }
        }
    }

    // MARK: - Playback

    /// Scheduled changes own all displays and keep the normal playback pause policy.
    func applyScheduledWallpaper(_ wallpaper: Wallpaper) {
        wallpaperMode = .same
        wallpaperModeRaw = WallpaperMode.same.rawValue
        setWallpaper(wallpaper, userInitiated: false)
    }

    private func holdAutomationForManualChoice() {
        TimeOfDayManager.shared.onManualChange()
        PlaylistManager.shared.onManualChange()
    }

    /// Sets wallpaper for all screens (same mode).
    /// PlaybackDelegate drives the renderer directly (#170); the broadcast
    /// notification fans out to observers like DynamicIslandController and
    /// ThemeManager that react to wallpaper changes.
    ///
    /// `userInitiated` distinguishes a deliberate user choice from an automatic
    /// switch (playlist / time-of-day). Only user-initiated applies feed the
    /// rating prompt — passive rotation isn't a "ask for a review" moment.
    func setWallpaper(_ wallpaper: Wallpaper, userInitiated: Bool = true) {
        if userInitiated { holdAutomationForManualChoice() }
        currentWallpaper = wallpaper
        lastWallpaperURL = wallpaper.url.path

        playbackDelegate?.playbackSetWallpaper(url: wallpaper.url)
        // A power condition can swallow this; don't claim it played.
        isPlaying = playbackDelegate?.playbackIsPlaying ?? false
        let started = isPlaying

        NotificationCenter.default.post(
            name: .wallpaperDidChange, object: wallpaper,
            userInfo: ["userInitiated": userInitiated]
        )
        NotificationCenter.default.post(name: .playbackStateDidChange, object: started)

        if userInitiated {
            RatingPromptManager.shared.recordWallpaperApplied()
        }

        Task { @MainActor in
            guard currentWallpaper?.url == wallpaper.url else { return }
            await widgetSync.syncCurrentWallpaper(wallpaper)
            await MainActor.run { widgetSync.syncPlaybackState(isPlaying: isPlaying) }
        }
    }

    /// Sets wallpaper for a specific screen (different mode).
    func setWallpaper(_ wallpaper: Wallpaper, for screen: NSScreen, userInitiated: Bool = true) {
        if userInitiated { holdAutomationForManualChoice() }
        let screenName = screen.localizedName
        displayAssignments.set(wallpaper.url, for: screen.wallpaperAssignmentKey)
        screenWallpapers[screenName] = wallpaper.id
        saveScreenWallpapers()

        playbackDelegate?.playbackSetWallpaper(url: wallpaper.url, for: screen)
        // A power condition can swallow this; don't claim it played.
        isPlaying = playbackDelegate?.playbackIsPlaying ?? false

        // The active screen's wallpaper is what DynamicAccent, DynamicIsland,
        // ThemeManager, and the widget should reflect. Without updating
        // currentWallpaper + posting .wallpaperDidChange these consumers
        // remain stuck on stale data whenever per-screen mode is used.
        let activeScreen = NSScreen.main ?? screen
        if screen == activeScreen {
            currentWallpaper = wallpaper
            lastWallpaperURL = wallpaper.url.path
            NotificationCenter.default.post(
                name: .wallpaperDidChange, object: wallpaper,
                userInfo: ["userInitiated": userInitiated]
            )
            if userInitiated {
                RatingPromptManager.shared.recordWallpaperApplied()
            }
            Task { @MainActor in
                guard currentWallpaper?.url == wallpaper.url else { return }
                await widgetSync.syncCurrentWallpaper(wallpaper)
                await MainActor.run { widgetSync.syncPlaybackState(isPlaying: isPlaying) }
            }
        }

        NotificationCenter.default.post(
            name: .screenWallpaperDidChange,
            object: ScreenWallpaperInfo(wallpaper: wallpaper, screen: screen)
        )
        NotificationCenter.default.post(name: .playbackStateDidChange, object: isPlaying)
    }

    func wallpaper(for screen: NSScreen) -> Wallpaper? {
        if wallpaperMode == .same { return currentWallpaper }
        switch displayAssignments.selection(for: screen.wallpaperAssignmentKey) {
        case .empty: return nil
        case .file(let url): return wallpapers.first { $0.url.standardizedFileURL == url }
        case .inherit: break
        }
        guard let wallpaperID = screenWallpapers[screen.localizedName] else {
            return currentWallpaper
        }
        return wallpapers.first { $0.id == wallpaperID }
    }

    func setWallpaperMode(_ mode: WallpaperMode) {
        holdAutomationForManualChoice()
        wallpaperMode = mode
        wallpaperModeRaw = mode.rawValue

        if mode == .same, let wallpaper = currentWallpaper {
            playbackDelegate?.playbackSetWallpaper(url: wallpaper.url)
            // A mode switch is something the user just did.
            NotificationCenter.default.post(
                name: .wallpaperDidChange, object: wallpaper,
                userInfo: ["userInitiated": true]
            )
        } else if mode == .different {
            playbackDelegate?.playbackApplyScreenWallpapers()
            NotificationCenter.default.post(name: .applyScreenWallpapers, object: nil)
        }
    }

    /// A targeted first playback preserves other displays, including displays
    /// with no wallpaper. Store paths before changing currentWallpaper.
    func applyOnboardingWallpaper(_ wallpaper: Wallpaper, to displayID: UInt32?) throws {
        if let displayID {
            guard let target = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
                throw OnboardingDemoError.displayDisconnected
            }
            let previous = NSScreen.screens.map { ($0, self.wallpaper(for: $0)?.url) }
            for (screen, url) in previous {
                displayAssignments.set(url, for: screen.wallpaperAssignmentKey)
            }
            wallpaperMode = .different
            wallpaperModeRaw = WallpaperMode.different.rawValue
            setWallpaper(wallpaper, for: target)
        } else {
            wallpaperMode = .same
            wallpaperModeRaw = WallpaperMode.same.rawValue
            setWallpaper(wallpaper)
        }
    }

    func togglePlayback() {
        let wantsToPlay = !isPlaying

        // The user is taking control: a later unlock or wake must not undo it.
        PowerManager.shared.userDidTogglePlayback()

        // Report what actually happened, not what was asked for. A power
        // condition can swallow the play request, and a menu bar reading
        // "Playing" over a still desktop is a far more damaging bug report
        // than one that honestly says "Paused".
        if wantsToPlay {
            isPlaying = playbackDelegate?.playbackPlay() ?? false
        } else {
            playbackDelegate?.playbackPause()
            isPlaying = false
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

}

// MARK: - Notification Names

extension Notification.Name {
    static let wallpaperDidChange = Notification.Name("wallpaperDidChange")
    static let playbackStateDidChange = Notification.Name("playbackStateDidChange")
    static let screenWallpaperDidChange = Notification.Name("screenWallpaperDidChange")
    static let applyScreenWallpapers = Notification.Name("applyScreenWallpapers")
    static let openMainWindow = Notification.Name("openMainWindow")
    /// Posted after `NSApp.setActivationPolicy` (and similar events) so the
    /// desktop overlay can re-pin itself. Policy flips tear down window
    /// backing stores and otherwise leave a black desktop.
    static let desktopWindowsNeedReassert = Notification.Name("desktopWindowsNeedReassert")
}

// MARK: - Screen Wallpaper Info

struct ScreenWallpaperInfo {
    let wallpaper: Wallpaper
    let screen: NSScreen
}
