import Foundation
import Combine

/// The scaling of Library videos that do not use the default, keyed by
/// standardized file path like loop ranges and Pause After overrides (#348).
/// Not actor-isolated: the desktop controller reads it synchronously while
/// loading a wallpaper. Choices stay on this Mac and do not follow a file
/// renamed outside Wallnetic.
final class WallpaperScalingStore: ObservableObject {
    static let shared = WallpaperScalingStore()
    static let key = "wallpaper.scaling.v1"

    /// Only non-default choices are kept; a missing path means Fill.
    @Published private(set) var scalings: [String: WallpaperScaling] = [:]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String: WallpaperScaling].self, from: data) {
            scalings = saved.filter { $0.value != .fill }
        }
    }

    static func scaling(for url: URL, in scalings: [String: WallpaperScaling]) -> WallpaperScaling {
        scalings[url.standardizedFileURL.path] ?? .fill
    }

    func scaling(for url: URL) -> WallpaperScaling {
        Self.scaling(for: url, in: scalings)
    }

    func setScaling(_ scaling: WallpaperScaling, for url: URL) {
        var next = scalings
        next[url.standardizedFileURL.path] = scaling == .fill ? nil : scaling
        save(next)
    }

    /// Forgets the choices of removed Library items, so a different video
    /// imported later at the same path starts from Fill.
    func removeScalings(for urls: Set<URL>) {
        var next = scalings
        for url in urls { next[url.standardizedFileURL.path] = nil }
        save(next)
    }

    private func save(_ next: [String: WallpaperScaling]) {
        guard next != scalings else { return }
        if let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: Self.key)
        }
        scalings = next
    }
}
