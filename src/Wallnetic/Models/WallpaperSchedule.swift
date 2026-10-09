import Foundation

struct DailyWallpaperRange: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var startMinute: Int
    var endMinute: Int
    var wallpaperPath: String

    var segments: [Range<Int>] {
        guard (0..<1440).contains(startMinute), (0...1440).contains(endMinute), startMinute != endMinute else { return [] }
        if endMinute > startMinute { return [startMinute..<endMinute] }
        return [startMinute..<1440, 0..<endMinute].filter { !$0.isEmpty }
    }
    func contains(minute: Int) -> Bool { segments.contains { $0.contains(minute) } }
    var durationMinutes: Int { segments.reduce(0) { $0 + $1.count } }

    static func timeLabel(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
    static func parseTime(_ text: String, allowsEndOfDay: Bool = false) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<60).contains(minute) else { return nil }
        if allowsEndOfDay && hour == 24 && minute == 0 { return 1440 }
        guard (0..<24).contains(hour) else { return nil }
        return hour * 60 + minute
    }
}

enum WallpaperScheduleError: LocalizedError {
    case invalidRange, overlap(String, String), invalidDuration, tooManyItems, invalidData
    var errorDescription: String? {
        switch self {
        case .invalidRange: return "Enter valid times. Start and end must differ; use 00:00–24:00 for a full day."
        case .overlap(let a, let b): return "\(a) overlaps \(b). Move a boundary or choose a different time."
        case .invalidDuration: return "Each duration must be between 1 and 86,400 seconds."
        case .tooManyItems: return "Use at most 96 daily ranges or 500 playlist items."
        case .invalidData: return "Saved settings could not be read. The original data has been kept."
        }
    }
}

enum DailyWallpaperSchedule {
    static func validate(_ ranges: [DailyWallpaperRange]) throws {
        guard ranges.count <= 96 else { throw WallpaperScheduleError.tooManyItems }
        guard Set(ranges.map(\.id)).count == ranges.count else { throw WallpaperScheduleError.invalidData }
        for (index, range) in ranges.enumerated() {
            guard !range.segments.isEmpty else { throw WallpaperScheduleError.invalidRange }
            for other in ranges.dropFirst(index + 1) {
                if range.segments.contains(where: { a in other.segments.contains { a.overlaps($0) } }) {
                    throw WallpaperScheduleError.overlap(range.name, other.name)
                }
            }
        }
    }

    /// Wall-clock matching: skipped DST minutes are skipped; repeated minutes
    /// match the same range both times. End boundaries are exclusive.
    static func active(in ranges: [DailyWallpaperRange], at date: Date, calendar: Calendar) -> DailyWallpaperRange? {
        guard date.timeIntervalSince1970.isFinite else { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = parts.hour, let minute = parts.minute else { return nil }
        return ranges.first { $0.contains(minute: hour * 60 + minute) }
    }

    /// Horizontal drags move a complete range, preserving its length across midnight.
    static func moving(_ range: DailyWallpaperRange, by minutes: Int) -> DailyWallpaperRange {
        guard range.durationMinutes > 0, range.durationMinutes < 1440 else { return range }
        var result = range
        result.startMinute = ((range.startMinute + minutes % 1440) % 1440 + 1440) % 1440
        let end = result.startMinute + range.durationMinutes
        result.endMinute = end <= 1440 ? end : end % 1440
        return result
    }
}

struct TimedWallpaperItem: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var wallpaperPath: String
    var durationSeconds: Int

    static func validate(_ items: [TimedWallpaperItem]) throws {
        guard items.count <= 500 else { throw WallpaperScheduleError.tooManyItems }
        guard Set(items.map(\.id)).count == items.count else { throw WallpaperScheduleError.invalidData }
        guard items.allSatisfy({ (1...86400).contains($0.durationSeconds) }) else { throw WallpaperScheduleError.invalidDuration }
    }
}

struct TimedPlaylistPosition: Equatable {
    let index: Int
    let secondsRemaining: TimeInterval

    /// Constant work per item even after years asleep; never replay missed changes.
    static func resolve(durations: [Int], anchor: Date, now: Date) -> Self? {
        guard !durations.isEmpty,
              durations.allSatisfy({ (1...86400).contains($0) }),
              anchor.timeIntervalSince1970.isFinite, now.timeIntervalSince1970.isFinite else { return nil }
        let total = durations.reduce(0.0) { $0 + Double($1) }
        let elapsed = max(0, now.timeIntervalSince(anchor))
        guard elapsed.isFinite else { return nil }
        var offset = elapsed.truncatingRemainder(dividingBy: total)
        for (index, duration) in durations.enumerated() {
            if offset < Double(duration) { return Self(index: index, secondsRemaining: Double(duration) - offset) }
            offset -= Double(duration)
        }
        return nil
    }
}

struct DailyScheduleDocument: Codable {
    var version = 1
    var ranges: [DailyWallpaperRange]
    var migrationNotice: String?

    static func migrating(_ defaults: UserDefaults) -> Self {
        let slots = ["morning", "afternoon", "evening", "night"]
        let fallback = [6, 12, 17, 21]
        var hours = zip(slots, fallback).map { (defaults.object(forKey: "tod.\($0.0)Hour") as? Int) ?? $0.1 }
        let valid = hours.allSatisfy { (0..<24).contains($0) } && zip(hours, hours.dropFirst()).allSatisfy { $0 < $1 }
        if !valid { hours = fallback }
        let ranges = slots.indices.map { i in
            DailyWallpaperRange(name: slots[i].capitalized, startMinute: hours[i] * 60,
                                endMinute: hours[(i + 1) % 4] * 60,
                                wallpaperPath: defaults.string(forKey: "tod.\(slots[i])WallpaperPath") ?? "")
        }
        return Self(ranges: ranges, migrationNotice: valid ? nil : "The previous start times were invalid or out of order. Default times were restored; all wallpaper selections were kept.")
    }
}

/// Versioned JSON writes retain a backup before an explicit edit replaces
/// unreadable settings. Failed reads never silently overwrite user data.
enum WallpaperSchedulePersistence {
    static func read<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) throws -> T? {
        guard let data = defaults.data(forKey: key) else {
            if defaults.object(forKey: key) != nil { throw WallpaperScheduleError.invalidData }
            return nil
        }
        guard data.count <= 1_048_576 else { throw WallpaperScheduleError.invalidData }
        return try JSONDecoder().decode(type, from: data)
    }
    static func write<T: Encodable>(_ value: T, key: String, defaults: UserDefaults, backup: Bool = false) throws {
        let data = try JSONEncoder().encode(value)
        guard data.count <= 1_048_576 else { throw WallpaperScheduleError.invalidData }
        if backup, let previous = defaults.object(forKey: key) {
            defaults.set(previous, forKey: key + ".recoveryBackup")
        }
        defaults.set(data, forKey: key)
    }
}
