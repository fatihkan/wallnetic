import AppKit
import Combine
import CryptoKit

/// The bundled original stays read-only. Each installation is a normal,
/// removable library copy with a unique name; user files are never overwritten.
@MainActor
final class OnboardingSampleInstaller {
    static let shared = OnboardingSampleInstaller(library: WallpaperManager.shared)
    static let maximumBytes = 2 * 1_024 * 1_024
    private let library: WallpaperReading & WallpaperWriting
    private let defaults: UserDefaults
    private let source: () -> URL?
    private let gate = ImportGate()
    private let pathKey = "onboarding.sample.aurora.path.v1"

    init(library: WallpaperReading & WallpaperWriting, defaults: UserDefaults = .standard,
         source: @escaping () -> URL? = { Bundle.main.url(forResource: "AuroraSample", withExtension: "mp4") }) {
        self.library = library
        self.defaults = defaults
        self.source = source
    }

    func install() async throws -> Wallpaper {
        try await gate.run { try await self.installOnce() }
    }

    private func installOnce() async throws -> Wallpaper {
        try Task.checkCancellation()
        guard let source = source(), let sourceData = boundedData(at: source) else {
            throw OnboardingDemoError.sampleUnavailable
        }
        if let path = defaults.string(forKey: pathKey),
           let existing = library.wallpapers.first(where: { $0.url.path == path }),
           let data = boundedData(at: existing.url), SHA256.hash(data: data) == SHA256.hash(data: sourceData) {
            return existing
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let copy = directory.appendingPathComponent("Aurora Sample - \(UUID().uuidString.prefix(8)).mp4")
        try sourceData.write(to: copy, options: .withoutOverwriting)
        let wallpaper = try await library.importVideo(from: copy)
        defaults.set(wallpaper.url.path, forKey: pathKey)
        return wallpaper
    }

    private func boundedData(at url: URL) -> Data? {
        guard url.isFileURL, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= Self.maximumBytes else { return nil }
        return try? Data(contentsOf: url)
    }
}

enum OnboardingDemoError: LocalizedError {
    case sampleUnavailable, displayDisconnected
    var errorDescription: String? {
        switch self {
        case .sampleUnavailable: return "The included sample is unavailable. You can still import your own video."
        case .displayDisconnected: return "That display is no longer connected. Choose a connected display and try again."
        }
    }
}

/// Owns an attempt, including cancellation when its sheet disappears. Imports
/// may finish copying, but a cancelled attempt must never change the desktop.
@MainActor
final class OnboardingDemoModel: ObservableObject {
    @Published private(set) var isWorking = false
    @Published private(set) var message: String?
    @Published private(set) var error: String?
    private var task: Task<Void, Never>?
    private var generation = 0
    private let sample: () async throws -> Wallpaper
    private let importVideo: (URL) async throws -> Wallpaper
    private let apply: (Wallpaper, UInt32?) throws -> Void

    init(sample: @escaping () async throws -> Wallpaper = { try await OnboardingSampleInstaller.shared.install() },
         importVideo: @escaping (URL) async throws -> Wallpaper = { try await WallpaperManager.shared.importVideo(from: $0) },
         apply: @escaping (Wallpaper, UInt32?) throws -> Void = { try WallpaperManager.shared.applyOnboardingWallpaper($0, to: $1) }) {
        self.sample = sample
        self.importVideo = importVideo
        self.apply = apply
    }

    @discardableResult
    func trySample(on display: UInt32?) -> Task<Void, Never>? {
        start(on: display, operation: sample)
    }

    @discardableResult
    func importFile(_ url: URL, on display: UInt32?) -> Task<Void, Never>? {
        start(on: display) { [importVideo] in
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            return try await importVideo(url)
        }
    }

    private func start(on display: UInt32?, operation: @escaping () async throws -> Wallpaper) -> Task<Void, Never>? {
        guard !isWorking else { return nil }
        isWorking = true
        error = nil
        message = nil
        generation += 1
        let generation = generation
        task = Task { [weak self] in
            do {
                let wallpaper = try await operation()
                try Task.checkCancellation()
                guard let self, generation == self.generation else { return }
                try self.apply(wallpaper, display)
                self.message = "Wallpaper applied. Playback follows your pause and power settings. Remove the sample from Library whenever you like."
            } catch is CancellationError {
                // Closing or cancelling onboarding is not an import error.
            } catch {
                guard let self, generation == self.generation else { return }
                self.error = error.localizedDescription
            }
            guard let self, generation == self.generation else { return }
            self.isWorking = false
            self.task = nil
        }
        return task
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        isWorking = false
        message = nil
    }

    func reportImportError(_ failure: Error) {
        let cocoa = failure as NSError
        guard cocoa.domain != NSCocoaErrorDomain || cocoa.code != NSUserCancelledError else { return }
        error = failure.localizedDescription
    }
}
