import AVFoundation
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
    private let trims: PlaybackTrimStore
    private var inspection: Task<Void, Never>?
    private var conversion: Task<Void, Never>?

    init(source: Wallpaper, optimizer: VideoOptimizing, library: WallpaperReading & WallpaperWriting,
         refreshLibrary: @escaping () -> Void = {}, trims: PlaybackTrimStore = .shared) {
        self.source = source
        self.optimizer = optimizer
        self.library = library
        self.refreshLibrary = refreshLibrary
        self.trims = trims
    }
    var unavailableReason: String? { info?.unavailable[preset] }
    var canStart: Bool { info != nil && unavailableReason == nil && !isLoading && !isWorking && result == nil }

    @discardableResult
    func load() -> Task<Void, Never> {
        inspection?.cancel()
        isLoading = true
        info = nil
        error = nil
        message = nil
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
                // is still valid if cancellation arrives immediately after that,
                // so the range is copied in a task the cancellation cannot reach.
                let source = self.source.url
                let loopRange = await Task { await self.inheritLoopRange(from: source, to: result.url) }.value
                refreshLibrary()
                self.result = result
                progress = 1
                switch loopRange {
                case .kept: message = "Copy added to Library with the same loop range. Your original is unchanged."
                case .dropped: message = "Copy added to Library. Its loop range could not be kept, so the copy plays in full. Your original is unchanged."
                case .none: message = "Copy added to Library. Your original is unchanged."
                }
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

    /// What became of the source's loop range on its copy.
    private enum CopiedLoopRange { case kept, dropped, none }

    /// A copy of a trimmed video loops the same part: the source's range moved
    /// to the copy's frames and clamped to its length, with the copy's own
    /// fingerprint. From then on each item's range is edited on its own.
    private func inheritLoopRange(from source: URL, to copy: URL) async -> CopiedLoopRange {
        guard let trim = TrimmedVideoAsset.usableTrim(trims.trim(for: source), for: source) else { return .none }
        guard let fingerprint = VideoFileFingerprint(fileAt: copy) else { return .dropped }
        let asset = AVURLAsset(url: copy, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { return .dropped }
            let (range, frameDuration) = try await track.load(.timeRange, .minFrameDuration)
            guard let copyTrim = trim.inherited(byTrack: range, frameDuration: frameDuration,
                                                fingerprint: fingerprint) else { return .dropped }
            try trims.setTrim(copyTrim, for: copy)
            return .kept
        } catch {
            Log.app.error("Optimized copy did not inherit the loop range: \(error.localizedDescription, privacy: .public)")
            return .dropped
        }
    }

    func cancel() {
        inspection?.cancel()
        inspection = nil
        isLoading = false
        if isWorking { isCancelling = true; conversion?.cancel() }
    }
    func apply(_ url: URL) {
        message = nil
        guard let wallpaper = library.wallpapers.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }), FileManager.default.fileExists(atPath: url.path) else {
            error = "That video is no longer in the library. Refresh the library and choose another wallpaper."
            return
        }
        library.setWallpaper(wallpaper, userInitiated: true)
        error = nil
        message = "Wallpaper selected. Your playback and pause settings still apply."
    }
}
