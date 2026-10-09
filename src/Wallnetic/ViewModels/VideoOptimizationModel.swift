import Combine
import Foundation

@MainActor
final class VideoOptimizationModel: ObservableObject {
    let source: Wallpaper
    @Published var preset: VideoOptimizationPreset = .balanced
    @Published private(set) var info: VideoOptimizationInfo?
    @Published private(set) var result: OptimizedVideoResult?
    @Published private(set) var isLoading = false
    @Published private(set) var isWorking = false
    @Published private(set) var isCancelling = false
    @Published private(set) var progress = 0.0
    @Published private(set) var message: String?
    @Published private(set) var error: String?
    private let optimizer: VideoOptimizing
    private let library: WallpaperReading & WallpaperWriting
    private let refreshLibrary: () -> Void
    private var inspection: Task<Void, Never>?
    private var conversion: Task<Void, Never>?

    init(source: Wallpaper, optimizer: VideoOptimizing, library: WallpaperReading & WallpaperWriting,
         refreshLibrary: @escaping () -> Void = {}) {
        self.source = source
        self.optimizer = optimizer
        self.library = library
        self.refreshLibrary = refreshLibrary
    }
    var unavailableReason: String? { info?.unavailable[preset] }
    var canStart: Bool { info != nil && unavailableReason == nil && !isLoading && !isWorking && result == nil }

    @discardableResult
    func load() -> Task<Void, Never> {
        inspection?.cancel()
        isLoading = true
        error = nil
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let info = try await optimizer.inspect(source.url)
                try Task.checkCancellation()
                self.info = info
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            if !Task.isCancelled { isLoading = false }
        }
        inspection = task
        return task
    }

    @discardableResult
    func start() -> Task<Void, Never>? {
        guard canStart else { return nil }
        isWorking = true
        isCancelling = false
        error = nil
        message = nil
        progress = 0
        let preset = preset
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await optimizer.optimize(source.url, preset: preset) { [weak self] value in
                    self?.progress = value.isFinite ? min(1, max(0, value)) : 0
                }
                // The service's final rename is its commit point. A completed copy
                // is still valid if cancellation arrives immediately after that.
                refreshLibrary()
                self.result = result
                progress = 1
                message = "Copy added to Library. Your original is unchanged."
            } catch is CancellationError {
                message = "Cancelled. No partial copy was added to Library."
            } catch { self.error = error.localizedDescription }
            isWorking = false
            isCancelling = false
            conversion = nil
        }
        conversion = task
        return task
    }

    func cancel() {
        inspection?.cancel()
        inspection = nil
        isLoading = false
        if isWorking { isCancelling = true; conversion?.cancel() }
    }
    func apply(_ url: URL) {
        guard let wallpaper = library.wallpapers.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }), FileManager.default.fileExists(atPath: url.path) else {
            error = "That video is no longer in the library. Refresh the library and choose another wallpaper."
            return
        }
        library.setWallpaper(wallpaper, userInitiated: true)
    }
}
