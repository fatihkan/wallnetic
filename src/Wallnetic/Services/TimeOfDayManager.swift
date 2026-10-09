import Foundation
import Combine

/// Main-thread owner of the daily wall-clock schedule. Initialization only
/// reads/migrates settings; playback starts after AppDelegate wires its delegate.
final class TimeOfDayManager: ObservableObject {
    static let shared: TimeOfDayManager = TimeOfDayManager(
        library: { WallpaperManager.shared.wallpapers },
        apply: { WallpaperManager.shared.applyScheduledWallpaper($0) },
        stopCompeting: { PlaylistManager.shared.stop() })
    static let documentKey = "tod.schedule.v1"

    @Published private(set) var isEnabled: Bool
    @Published private(set) var ranges: [DailyWallpaperRange] = []
    @Published private(set) var activeRangeID: UUID?
    @Published private(set) var status = "Daily schedule is off."
    @Published private(set) var error: String?
    @Published private(set) var migrationNotice: String?
    @Published private(set) var manualOverrideUntil: Date?

    private let defaults: UserDefaults
    private let library: () -> [Wallpaper]
    private let apply: (Wallpaper) -> Void
    private let stopCompeting: () -> Void
    private let now: () -> Date
    private let calendar: () -> Calendar
    private let fileExists: (URL) -> Bool
    private let runtime: WallpaperAutomationRuntime
    private var lastAppliedPath: String?
    private var unreadableDocument = false
    private let overrideKey = "tod.manualOverrideUntil"

    init(defaults: UserDefaults = .standard,
         library: @escaping () -> [Wallpaper], apply: @escaping (Wallpaper) -> Void,
         stopCompeting: @escaping () -> Void = {}, now: @escaping () -> Date = Date.init,
         calendar: @escaping () -> Calendar = { .autoupdatingCurrent },
         fileExists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
         observesSystem: Bool = true) {
        self.defaults = defaults
        self.library = library
        self.apply = apply
        self.stopCompeting = stopCompeting
        self.now = now
        self.calendar = calendar
        self.fileExists = fileExists
        runtime = WallpaperAutomationRuntime(observesSystem: observesSystem)
        isEnabled = defaults.bool(forKey: "tod.enabled")
        if let date = defaults.object(forKey: overrideKey) as? Date, date.timeIntervalSince1970.isFinite {
            manualOverrideUntil = date
        }
        do {
            if let saved = try WallpaperSchedulePersistence.read(DailyScheduleDocument.self, key: Self.documentKey, defaults: defaults) {
                guard saved.version == 1 else { throw WallpaperScheduleError.invalidData }
                try DailyWallpaperSchedule.validate(saved.ranges)
                ranges = saved.ranges
                migrationNotice = saved.migrationNotice
            } else {
                let migrated = DailyScheduleDocument.migrating(defaults)
                try DailyWallpaperSchedule.validate(migrated.ranges)
                try WallpaperSchedulePersistence.write(migrated, key: Self.documentKey, defaults: defaults)
                ranges = migrated.ranges
                migrationNotice = migrated.migrationNotice
            }
        } catch {
            unreadableDocument = true
            self.error = WallpaperScheduleError.invalidData.localizedDescription
        }
    }

    func start(restoring: Bool = false) {
        stopCompeting()
        isEnabled = true
        defaults.set(true, forKey: "tod.enabled")
        defaults.set("daily", forKey: WallpaperAutomation.ownerKey)
        if !restoring { clearOverride() }
        lastAppliedPath = nil
        runtime.start { [weak self] in self?.evaluate() }
        evaluate()
    }

    func stop() {
        isEnabled = false
        defaults.set(false, forKey: "tod.enabled")
        runtime.stop()
        activeRangeID = nil
        status = "Daily schedule is off."
        lastAppliedPath = nil
    }

    @discardableResult
    func save(_ candidate: [DailyWallpaperRange]) -> Bool {
        do {
            try DailyWallpaperSchedule.validate(candidate)
            try WallpaperSchedulePersistence.write(DailyScheduleDocument(ranges: candidate),
                key: Self.documentKey, defaults: defaults, backup: unreadableDocument)
            ranges = candidate
            unreadableDocument = false
            migrationNotice = nil
            error = nil
            lastAppliedPath = nil
            evaluate()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func save(_ range: DailyWallpaperRange) -> Bool {
        var candidate = ranges
        if let index = candidate.firstIndex(where: { $0.id == range.id }) { candidate[index] = range }
        else { candidate.append(range) }
        return save(candidate)
    }

    func remove(_ id: UUID) { _ = save(ranges.filter { $0.id != id }) }
    func dismissError() { error = nil }

    func removeWallpaperPaths(_ paths: Set<String>) {
        guard ranges.contains(where: { paths.contains($0.wallpaperPath) }) else { return }
        let candidate = ranges.map { range -> DailyWallpaperRange in
            var range = range
            if paths.contains(range.wallpaperPath) { range.wallpaperPath = "" }
            return range
        }
        _ = save(candidate)
    }

    func onManualChange() {
        guard isEnabled else { return }
        manualOverrideUntil = now().addingTimeInterval(1800)
        defaults.set(manualOverrideUntil, forKey: overrideKey)
        lastAppliedPath = nil
        evaluate()
    }

    func resumeNow() {
        clearOverride()
        lastAppliedPath = nil
        evaluate()
    }

    private func clearOverride() {
        manualOverrideUntil = nil
        defaults.removeObject(forKey: overrideKey)
    }

    func evaluate() {
        guard isEnabled else { return }
        let date = now()
        guard date.timeIntervalSince1970.isFinite else { return }
        var delay = 60 - date.timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
        defer { runtime.schedule(after: delay) }
        if let until = manualOverrideUntil, until > date {
            status = "Manual choice until " + until.formatted(date: .omitted, time: .shortened) + "."
            delay = min(delay, until.timeIntervalSince(date))
            return
        }
        if manualOverrideUntil != nil { clearOverride() }
        guard !unreadableDocument else { status = "Saved schedule needs attention. Current wallpaper kept."; return }
        guard let range = DailyWallpaperSchedule.active(in: ranges, at: date, calendar: calendar()) else {
            activeRangeID = nil
            lastAppliedPath = nil
            status = "No range now. Current wallpaper kept."
            return
        }
        activeRangeID = range.id
        guard let wallpaper = library().first(where: { $0.url.path == range.wallpaperPath }), fileExists(wallpaper.url) else {
            lastAppliedPath = nil
            status = range.name + ": wallpaper missing or unassigned. Current wallpaper kept."
            return
        }
        status = range.name + " · " + wallpaper.displayName
        guard lastAppliedPath != wallpaper.url.path else { return }
        lastAppliedPath = wallpaper.url.path
        apply(wallpaper)
    }
}
