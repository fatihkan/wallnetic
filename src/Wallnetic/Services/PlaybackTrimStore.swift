import Foundation
import Combine

/// Loop ranges of Library videos, keyed by standardized file path like Pause
/// After overrides and optimized-copy records. Not actor-isolated: the desktop
/// controller reads it synchronously while loading a wallpaper. Ranges stay
/// on this Mac and do not follow a file renamed outside Wallnetic.
final class PlaybackTrimStore: ObservableObject {
    static let shared = PlaybackTrimStore()
    static let key = "playback.loopRanges.v1"
    private struct Document: Codable { var version = 1; var trims: [String: PlaybackTrim] }

    @Published private(set) var trims: [String: PlaybackTrim] = [:]
    /// Paths whose range a renderer could not build, so the full video plays.
    /// Not saved: the next load reports again, and an edit clears the mark.
    @Published private(set) var unbuiltPaths: Set<String> = []
    private let defaults: UserDefaults
    /// Saved ranges that could not be read. They are kept as a recovery backup
    /// when the next edit replaces them, never silently discarded.
    private(set) var isUnreadable = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        do {
            if let saved = try WallpaperSchedulePersistence.read(Document.self, key: Self.key, defaults: defaults) {
                guard saved.version == 1 else { throw WallpaperScheduleError.invalidData }
                trims = saved.trims
            }
        } catch { isUnreadable = true }
    }

    static func trim(for url: URL, in trims: [String: PlaybackTrim]) -> PlaybackTrim? {
        trims[url.standardizedFileURL.path]
    }

    func trim(for url: URL) -> PlaybackTrim? {
        Self.trim(for: url, in: trims)
    }

    func isUnbuilt(_ url: URL) -> Bool {
        unbuiltPaths.contains(url.standardizedFileURL.path)
    }

    /// Records whether a renderer applied the video's range after loading it.
    func noteTrim(applied: Bool, for url: URL) {
        let path = url.standardizedFileURL.path
        guard unbuiltPaths.contains(path) == applied else { return }
        if applied { unbuiltPaths.remove(path) } else { unbuiltPaths.insert(path) }
    }

    /// Stores a video's range; nil removes it.
    func setTrim(_ trim: PlaybackTrim?, for url: URL) throws {
        var next = trims
        next[url.standardizedFileURL.path] = trim
        guard next != trims else { return }
        try save(next)
    }

    /// Forgets the ranges of removed Library items, so a different video
    /// imported later at the same path plays in full. Removal URLs are
    /// standardized like the stored keys.
    func removeTrims(for urls: Set<URL>) {
        var next = trims
        for url in urls { next[url.standardizedFileURL.path] = nil }
        guard next != trims else { return }
        do {
            try save(next)
        } catch {
            Log.app.error("Could not prune loop ranges: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save(_ next: [String: PlaybackTrim]) throws {
        try WallpaperSchedulePersistence.write(Document(trims: next), key: Self.key, defaults: defaults,
                                               backup: isUnreadable)
        isUnreadable = false
        let edited = Set(next.keys).union(trims.keys).filter { next[$0] != trims[$0] }
        trims = next
        if !unbuiltPaths.isDisjoint(with: edited) { unbuiltPaths.subtract(edited) }
    }
}
