import Foundation
import SwiftUI

/// Automatically rotates the desktop wallpaper on an interval (v1.4 Wave 1).
///
/// The most-requested feature across multiple sources ("let it continuously
/// shuffle"). It builds on `WallpaperManager`'s existing apply path — it just
/// picks the next wallpaper from a chosen source on a timer and hands it to
/// `setWallpaper(_:)`, so transitions, widget sync, per-display mode and the
/// system-wallpaper still-frame all keep working unchanged.
///
/// Mutually exclusive with `TimeOfDayManager` (both auto-switch). Exclusion is
/// enforced at the user-facing entry points (`enableExclusively()` / the
/// settings toggles), never from `init`/`start`, so the two singletons can't
/// re-enter each other during launch.
class PlaylistManager: ObservableObject {
    static let shared = PlaylistManager()

    // MARK: - Source & order

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
        switch seconds {
        case ..<3600:
            let minutes = seconds / 60
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        case ..<86400:
            let hours = seconds / 3600
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        default:
            return "Daily"
        }
    }

    // MARK: - Settings (persisted)

    @AppStorage("playlist.enabled") var isEnabled: Bool = false
    @AppStorage("playlist.intervalSeconds") var intervalSeconds: Int = 1800
    /// Raw storage bound directly by the Pickers; logic reads `order`/`source`.
    @AppStorage("playlist.order") var orderRaw: String = Order.shuffle.rawValue
    @AppStorage("playlist.source") var sourceRaw: String = Source.library.rawValue
    @AppStorage("playlist.collectionID") var collectionIDString: String = ""

    var order: Order { Order(rawValue: orderRaw) ?? .shuffle }
    var source: Source { Source(rawValue: sourceRaw) ?? .library }

    private var timer: Timer?

    private init() {
        if isEnabled { start() }
    }

    // MARK: - Control

    /// Start rotating. Pure (no cross-manager calls) so it is safe to call
    /// from `init` at launch.
    func start() {
        isEnabled = true
        scheduleTimer()
    }

    func stop() {
        isEnabled = false
        timer?.invalidate()
        timer = nil
    }

    /// User-initiated enable. Turns off time-of-day switching first so the two
    /// schedulers never fight over the wallpaper.
    func enableExclusively() {
        TimeOfDayManager.shared.stop()
        start()
    }

    func toggle() {
        if isEnabled { stop() } else { enableExclusively() }
    }

    /// Re-arm the timer after the interval changes while running.
    func reschedule() {
        guard isEnabled else { return }
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = TimeInterval(max(1, intervalSeconds))
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.advance()
        }
        // .common so it keeps firing during menu tracking / live resize.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Rotation

    /// Advance to the next wallpaper in the current source and order.
    func advance() {
        let wallpapers = currentSourceWallpapers()
        guard wallpapers.count > 1 else { return }  // nothing to rotate to

        let currentID = WallpaperManager.shared.currentWallpaper?.id
        let currentIndex = currentID.flatMap { id in
            wallpapers.firstIndex(where: { $0.id == id })
        }

        let nextIndex: Int?
        switch order {
        case .sequential:
            nextIndex = Self.nextSequentialIndex(current: currentIndex, count: wallpapers.count)
        case .shuffle:
            nextIndex = Self.shuffleCandidates(count: wallpapers.count, current: currentIndex).randomElement()
        }

        guard let nextIndex, wallpapers.indices.contains(nextIndex) else { return }
        Log.app.info("Playlist advancing (\(self.order.rawValue, privacy: .public)) to \(wallpapers[nextIndex].name, privacy: .public)")
        // Automatic rotation — don't feed the rating prompt.
        WallpaperManager.shared.setWallpaper(wallpapers[nextIndex], userInitiated: false)
    }

    private func currentSourceWallpapers() -> [Wallpaper] {
        switch source {
        case .library:
            return WallpaperManager.shared.wallpapers
        case .favorites:
            return WallpaperManager.shared.wallpapers.filter { $0.isFavorite }
        case .collection:
            guard let uuid = UUID(uuidString: collectionIDString),
                  let collection = CollectionManager.shared.collections.first(where: { $0.id == uuid })
            else { return [] }
            return CollectionManager.shared.wallpapers(in: collection)
        }
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
