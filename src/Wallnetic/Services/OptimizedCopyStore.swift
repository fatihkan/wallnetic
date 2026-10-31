import Foundation
import Combine

struct OptimizedCopyRecord: Codable, Equatable {
    let sourcePath: String
    let copyPath: String
    let preset: VideoOptimizationPreset
}

/// Relationships only. File deletion always goes through normal library cleanup.
@MainActor
final class OptimizedCopyStore: ObservableObject {
    static let shared = OptimizedCopyStore()
    static let key = "video.optimizedCopies.v1"
    private struct Document: Codable { var version = 1; var records: [OptimizedCopyRecord] }
    @Published private(set) var records: [OptimizedCopyRecord] = []
    private let defaults: UserDefaults
    private var unreadable = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        do {
            if let saved = try WallpaperSchedulePersistence.read(Document.self, key: Self.key, defaults: defaults) {
                guard saved.version == 1 else { throw WallpaperScheduleError.invalidData }
                records = saved.records
            }
        } catch { unreadable = true }
    }
    func record(_ record: OptimizedCopyRecord) throws {
        let candidate = records.filter { $0.copyPath != record.copyPath } + [record]
        try WallpaperSchedulePersistence.write(Document(records: candidate), key: Self.key, defaults: defaults, backup: unreadable)
        records = candidate
        unreadable = false
    }
    func originalPath(for copy: URL) -> String? {
        records.first { URL(fileURLWithPath: $0.copyPath).standardizedFileURL == copy.standardizedFileURL }?.sourcePath
    }
    func removeCopies(at paths: Set<String>) {
        let normalized = Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        let candidate = records.filter { !normalized.contains(URL(fileURLWithPath: $0.copyPath).standardizedFileURL.path) }
        guard candidate != records else { return }
        do {
            try WallpaperSchedulePersistence.write(Document(records: candidate), key: Self.key, defaults: defaults)
            records = candidate
        } catch { Log.app.error("Could not prune optimized copy relationships: \(error.localizedDescription, privacy: .public)") }
    }
}
