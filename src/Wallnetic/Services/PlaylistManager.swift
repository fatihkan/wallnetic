import Foundation
import Combine

struct PlaylistDurationDocument: Codable {
    var version = 1
    var items: [TimedWallpaperItem] = []
    var initializedFromSource = false
}

struct PlaylistPlaybackProgress: Codable {
    var version = 1
    var anchor: Date
    var orderedPaths: [String]
    var configuration: String
}

/// An elapsed-time playlist. A persisted cycle anchor handles sleep/relaunch
/// without replaying missed transitions; timezone changes do not alter durations.
final class PlaylistManager: ObservableObject {
    static let shared: PlaylistManager = PlaylistManager(
        library: { WallpaperManager.shared.wallpapers },
        currentPath: { WallpaperManager.shared.currentWallpaper?.url.path },
        collectionItems: { id in
            guard let collection = CollectionManager.shared.collections.first(where: { $0.id == id }) else { return [] }
            return CollectionManager.shared.wallpapers(in: collection)
        },
        apply: { WallpaperManager.shared.applyScheduledWallpaper($0) },
        stopCompeting: { TimeOfDayManager.shared.stop() })
    static let documentKey = "playlist.durations.v1"
    static let progressKey = "playlist.progress.v1"

    enum Source: String, CaseIterable, Identifiable {
        case library, favorites, collection
        var id: String { rawValue }
        var label: String {
            switch self {
            case .library: return "Whole Library"
            case .favorites: return "Favorites"
            case .collection: return "Collection"
            }
        }
    }

    enum Order: String, CaseIterable, Identifiable {
        case shuffle, sequential
        var id: String { rawValue }
        var label: String {
            switch self {
            case .shuffle: return "Shuffle"
            case .sequential: return "In order"
            }
        }
    }

    /// Selectable rotation intervals in seconds (5/15/30 min, 1/6 hr, daily).
    static let intervalOptions: [Int] = [300, 900, 1800, 3600, 21600, 86400]

    static func intervalLabel(_ seconds: Int) -> String {
        if seconds == 86400 { return "Daily" }
        if seconds >= 3600 && seconds % 3600 == 0 {
            let hours = seconds / 3600
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }
        if seconds >= 60 && seconds % 60 == 0 {
            let minutes = seconds / 60
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        return "\(seconds) second\(seconds == 1 ? "" : "s")"
    }

    @Published private(set) var isEnabled: Bool
    @Published private(set) var usesItemDurations: Bool
    @Published private(set) var items: [TimedWallpaperItem] = []
    @Published private(set) var status = "Playlist is off."
    @Published private(set) var error: String?
    @Published private(set) var manualOverrideUntil: Date?
    @Published private(set) var activeItemID: UUID?

    @Published var intervalSeconds: Int {
        didSet { defaults.set(intervalSeconds, forKey: "playlist.intervalSeconds"); configurationChanged() }
    }
    @Published var orderRaw: String {
        didSet { defaults.set(orderRaw, forKey: "playlist.order"); configurationChanged() }
    }
    @Published var sourceRaw: String {
        didSet { defaults.set(sourceRaw, forKey: "playlist.source"); configurationChanged() }
    }
    @Published var collectionIDString: String {
        didSet { defaults.set(collectionIDString, forKey: "playlist.collectionID"); configurationChanged() }
    }
    var order: Order { Order(rawValue: orderRaw) ?? .shuffle }
    var source: Source { Source(rawValue: sourceRaw) ?? .library }

    private let defaults: UserDefaults
    private let library: () -> [Wallpaper]
    private let currentPath: () -> String?
    private let collectionItems: (UUID) -> [Wallpaper]
    private let apply: (Wallpaper) -> Void
    private let stopCompeting: () -> Void
    private let now: () -> Date
    private let fileExists: (URL) -> Bool
    private let runtime: WallpaperAutomationRuntime
    private var progress: PlaylistPlaybackProgress?
    private var initializedFromSource = false
    private var unreadableDocument = false
    private var unreadableProgress = false
    private var lastAppliedPath: String?
    private var preferNextInitial = false
    private let overrideKey = "playlist.manualOverrideUntil"

    init(defaults: UserDefaults = .standard,
         library: @escaping () -> [Wallpaper], currentPath: @escaping () -> String? = { nil },
         collectionItems: @escaping (UUID) -> [Wallpaper] = { _ in [] },
         apply: @escaping (Wallpaper) -> Void, stopCompeting: @escaping () -> Void = {},
         now: @escaping () -> Date = Date.init,
         fileExists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
         observesSystem: Bool = true) {
        self.defaults = defaults
        self.library = library
        self.currentPath = currentPath
        self.collectionItems = collectionItems
        self.apply = apply
        self.stopCompeting = stopCompeting
        self.now = now
        self.fileExists = fileExists
        runtime = WallpaperAutomationRuntime(observesSystem: observesSystem)
        isEnabled = defaults.bool(forKey: "playlist.enabled")
        usesItemDurations = defaults.bool(forKey: "playlist.useItemDurations")
        intervalSeconds = max(1, min(86400, defaults.object(forKey: "playlist.intervalSeconds") as? Int ?? 1800))
        orderRaw = Order(rawValue: defaults.string(forKey: "playlist.order") ?? "")?.rawValue ?? Order.shuffle.rawValue
        sourceRaw = Source(rawValue: defaults.string(forKey: "playlist.source") ?? "")?.rawValue ?? Source.library.rawValue
        collectionIDString = defaults.string(forKey: "playlist.collectionID") ?? ""
        if let date = defaults.object(forKey: overrideKey) as? Date, date.timeIntervalSince1970.isFinite { manualOverrideUntil = date }
        do {
            if let saved = try WallpaperSchedulePersistence.read(PlaylistDurationDocument.self, key: Self.documentKey, defaults: defaults) {
                guard saved.version == 1 else { throw WallpaperScheduleError.invalidData }
                try TimedWallpaperItem.validate(saved.items)
                items = saved.items
                initializedFromSource = saved.initializedFromSource
            }
        } catch { unreadableDocument = true; self.error = WallpaperScheduleError.invalidData.localizedDescription }
        do {
            if let saved = try WallpaperSchedulePersistence.read(PlaylistPlaybackProgress.self, key: Self.progressKey, defaults: defaults) {
                guard saved.version == 1, saved.anchor.timeIntervalSince1970.isFinite,
                      Set(saved.orderedPaths).count == saved.orderedPaths.count else {
                    throw WallpaperScheduleError.invalidData
                }
                progress = saved
            }
        } catch { unreadableProgress = true }
    }

    func start(restoring: Bool = false) {
        stopCompeting()
        isEnabled = true
        defaults.set(true, forKey: "playlist.enabled")
        defaults.set("playlist", forKey: WallpaperAutomation.ownerKey)
        if !restoring {
            clearOverride()
            progress = nil
            preferNextInitial = true
        }
        lastAppliedPath = nil
        runtime.start { [weak self] in self?.evaluate() }
        evaluate()
    }
    func enableExclusively() { start() }
    func toggle() { if isEnabled { stop() } else { start() } }
    func stop() {
        isEnabled = false
        defaults.set(false, forKey: "playlist.enabled")
        runtime.stop()
        status = "Playlist is off."
        activeItemID = nil
        lastAppliedPath = nil
    }

    @discardableResult
    func setUsesItemDurations(_ enabled: Bool) -> Bool {
        if enabled && !initializedFromSource && !unreadableDocument {
            let migrated = sourceWallpapers().map {
                TimedWallpaperItem(name: $0.displayName, wallpaperPath: $0.url.path, durationSeconds: intervalSeconds)
            }
            guard persistItems(migrated) else { return false }
        }
        usesItemDurations = enabled
        defaults.set(enabled, forKey: "playlist.useItemDurations")
        configurationChanged()
        return true
    }

    @discardableResult
    func saveItems(_ candidate: [TimedWallpaperItem]) -> Bool {
        guard persistItems(candidate) else { return false }
        configurationChanged()
        return true
    }

    private func persistItems(_ candidate: [TimedWallpaperItem]) -> Bool {
        do {
            try TimedWallpaperItem.validate(candidate)
            try WallpaperSchedulePersistence.write(PlaylistDurationDocument(items: candidate, initializedFromSource: true),
                key: Self.documentKey, defaults: defaults, backup: unreadableDocument)
            items = candidate
            initializedFromSource = true
            unreadableDocument = false
            error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func save(_ item: TimedWallpaperItem) -> Bool {
        var candidate = items
        if let index = candidate.firstIndex(where: { $0.id == item.id }) { candidate[index] = item }
        else { candidate.append(item) }
        return saveItems(candidate)
    }
    func remove(_ id: UUID) { _ = saveItems(items.filter { $0.id != id }) }
    func move(_ id: UUID, by offset: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }), items.indices.contains(index + offset) else { return }
        var candidate = items
        candidate.swapAt(index, index + offset)
        _ = saveItems(candidate)
    }
    func removeWallpaperPaths(_ paths: Set<String>) {
        guard items.contains(where: { paths.contains($0.wallpaperPath) }) else { evaluate(); return }
        _ = saveItems(items.map { item in
            var item = item
            if paths.contains(item.wallpaperPath) { item.wallpaperPath = "" }
            return item
        })
    }
    func dismissError() { error = nil }
    func reschedule() { configurationChanged() }

    private func configurationChanged() {
        progress = nil
        if unreadableProgress, let original = defaults.object(forKey: Self.progressKey) {
            defaults.set(original, forKey: Self.progressKey + ".recoveryBackup")
            unreadableProgress = false
        }
        defaults.removeObject(forKey: Self.progressKey)
        lastAppliedPath = nil
        preferNextInitial = false
        evaluate()
    }
    func onManualChange() {
        guard isEnabled else { return }
        manualOverrideUntil = now().addingTimeInterval(1800)
        defaults.set(manualOverrideUntil, forKey: overrideKey)
        lastAppliedPath = nil
        evaluate()
    }
    func resumeNow() { clearOverride(); lastAppliedPath = nil; evaluate() }
    private func clearOverride() { manualOverrideUntil = nil; defaults.removeObject(forKey: overrideKey) }

    private var configuration: String {
        [usesItemDurations ? "items" : "source", sourceRaw, orderRaw, collectionIDString, String(intervalSeconds)].joined(separator: "|")
    }
    private func persistProgress() {
        guard let progress else { return }
        do {
            try WallpaperSchedulePersistence.write(progress, key: Self.progressKey, defaults: defaults, backup: unreadableProgress)
            unreadableProgress = false
        } catch { self.error = error.localizedDescription }
    }

    func sourceWallpapers() -> [Wallpaper] {
        let sourceItems: [Wallpaper]
        switch source {
        case .library: sourceItems = library()
        case .favorites: sourceItems = library().filter(\.isFavorite)
        case .collection: sourceItems = UUID(uuidString: collectionIDString).map(collectionItems) ?? []
        }
        var seen = Set<String>()
        return sourceItems.filter { seen.insert($0.url.path).inserted }
    }

    private func effectiveItems(at date: Date) -> [TimedWallpaperItem] {
        if usesItemDurations {
            if progress?.configuration != configuration {
                progress = PlaylistPlaybackProgress(anchor: date, orderedPaths: [], configuration: configuration)
                persistProgress()
            }
            let available = Set(library().filter { fileExists($0.url) }.map { $0.url.path })
            return items.filter { available.contains($0.wallpaperPath) }
        }
        let source = sourceWallpapers().filter { fileExists($0.url) }
        let paths = source.map { $0.url.path }
        if progress?.configuration != configuration || Set(progress?.orderedPaths ?? []) != Set(paths) {
            var orderPaths = order == .shuffle ? paths.shuffled() : paths
            if let path = currentPath(), let index = orderPaths.firstIndex(of: path), !orderPaths.isEmpty {
                let start = preferNextInitial && orderPaths.count > 1 ? (index + 1) % orderPaths.count : index
                orderPaths = Array(orderPaths[start...]) + Array(orderPaths[..<start])
            }
            preferNextInitial = false
            progress = PlaylistPlaybackProgress(anchor: date, orderedPaths: orderPaths, configuration: configuration)
            persistProgress()
        }
        let lookup = Dictionary(source.map { ($0.url.path, $0) }, uniquingKeysWith: { first, _ in first })
        return (progress?.orderedPaths ?? []).compactMap { path in
            lookup[path].map { TimedWallpaperItem(name: $0.displayName, wallpaperPath: path, durationSeconds: max(1, min(86400, intervalSeconds))) }
        }
    }

    func evaluate() {
        guard isEnabled else { return }
        let date = now()
        guard date.timeIntervalSince1970.isFinite else { return }
        var delay: TimeInterval = 60
        defer { runtime.schedule(after: delay) }
        if let until = manualOverrideUntil, until > date {
            status = "Manual choice until " + until.formatted(date: .omitted, time: .shortened) + "."
            delay = until.timeIntervalSince(date)
            return
        }
        if manualOverrideUntil != nil { clearOverride() }
        if usesItemDurations && unreadableDocument { status = "Saved playlist needs attention. Current wallpaper kept."; return }
        let effective = effectiveItems(at: date)
        if let anchor = progress?.anchor, date < anchor {
            progress?.anchor = date // A backwards clock adjustment starts a fresh cycle.
            persistProgress()
        }
        guard let anchor = progress?.anchor,
              let position = TimedPlaylistPosition.resolve(durations: effective.map(\.durationSeconds), anchor: anchor, now: date),
              let wallpaper = library().first(where: { $0.url.path == effective[position.index].wallpaperPath }) else {
            activeItemID = nil
            lastAppliedPath = nil
            status = "No available playlist wallpapers. Current wallpaper kept."
            return
        }
        let item = effective[position.index]
        activeItemID = usesItemDurations ? item.id : nil
        let missing = usesItemDurations ? items.count - effective.count : 0
        status = wallpaper.displayName + (missing > 0 ? " · \(missing) unavailable item(s) skipped." : "")
        delay = position.secondsRemaining
        guard lastAppliedPath != wallpaper.url.path else { return }
        lastAppliedPath = wallpaper.url.path
        apply(wallpaper)
    }

    /// Explicit next-item action advances the cycle without resetting its order.
    func advance() {
        let date = now()
        let effective = effectiveItems(at: date)
        guard let anchor = progress?.anchor,
              let position = TimedPlaylistPosition.resolve(durations: effective.map(\.durationSeconds), anchor: anchor, now: date) else { return }
        progress?.anchor = anchor.addingTimeInterval(-position.secondsRemaining)
        persistProgress()
        evaluate()
    }

    // MARK: - Index selection (pure, unit-testable)

    /// Next index in sequential order, wrapping around. Returns 0 when the
    /// current item is unknown, `nil` only for an empty set.
    static func nextSequentialIndex(current: Int?, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let current, current >= 0, current < count else { return 0 }
        return (current + 1) % count
    }

    /// Candidate indices to shuffle among: every index except the current one
    /// (so we never immediately repeat), unless there is only a single item.
    static func shuffleCandidates(count: Int, current: Int?) -> [Int] {
        guard count > 0 else { return [] }
        guard count > 1, let current, current >= 0, current < count else {
            return Array(0..<count)
        }
        return Array(0..<count).filter { $0 != current }
    }
}
