import Foundation
import Combine

/// Zero means never; a missing override means inherit. Paths match the library's
/// other persisted metadata and remain stable when its UUIDs are reconstructed.
final class PauseAfterSettings: ObservableObject {
    static let shared = PauseAfterSettings()
    static let storageKey = "playback.pauseAfter.v1"
    static let maximumSeconds = 86_400
    static let presets = [15, 30, 60, 300, 900]

    struct Preferences: Codable, Equatable {
        var defaultSeconds = 0
        var overrides: [String: Int] = [:]
        var replayWhenDesktopClears = false

        func duration(for url: URL) -> TimeInterval? {
            let seconds = overrides[url.standardizedFileURL.path] ?? defaultSeconds
            return seconds > 0 ? TimeInterval(seconds) : nil
        }
    }

    @Published private(set) var preferences: Preferences
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var saved = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        saved.defaultSeconds = Self.validated(saved.defaultSeconds)
        saved.overrides = saved.overrides.mapValues(Self.validated)
        preferences = saved
    }

    func setDefault(seconds: Int) {
        var next = preferences
        next.defaultSeconds = Self.validated(seconds)
        save(next)
    }

    func setOverride(seconds: Int?, for url: URL) {
        var next = preferences
        next.overrides[url.standardizedFileURL.path] = seconds.map(Self.validated)
        save(next)
    }

    func setReplayWhenDesktopClears(_ enabled: Bool) {
        var next = preferences
        next.replayWhenDesktopClears = enabled
        save(next)
    }

    private func save(_ next: Preferences) {
        guard next != preferences, let data = try? JSONEncoder().encode(next) else { return }
        defaults.set(data, forKey: Self.storageKey)
        preferences = next
    }

    private static func validated(_ seconds: Int) -> Int {
        (0...maximumSeconds).contains(seconds) ? seconds : 0
    }
}
