import XCTest
import AppKit
@testable import Wallnetic

@MainActor
final class VideoOptimizationModelTests: XCTestCase {
    private var root: URL!
    private var library: OptimizationLibrarySpy!
    private var exporter: OptimizationExporterSpy!
    private var source: Wallpaper!
    private var result: OptimizedVideoResult!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("Original.mp4"), copy = root.appendingPathComponent("Copy.mp4")
        try Data([1]).write(to: original)
        try Data([2]).write(to: copy)
        source = Wallpaper(url: original)
        result = OptimizedVideoResult(url: copy, sourceBytes: 10, outputBytes: 5, duration: 1, size: CGSize(width: 640, height: 360), frameRate: 15)
        library = OptimizationLibrarySpy()
        library.wallpapers = [source, Wallpaper(url: copy)]
        exporter = OptimizationExporterSpy(result: result)
    }
    override func tearDownWithError() throws {
        if let root, FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }

    func testOptInConversionReportsProgressAndDoesNotApplyAutomatically() async throws {
        var refreshed = 0
        let model = VideoOptimizationModel(source: source, optimizer: exporter, library: library, refreshLibrary: { refreshed += 1 })
        XCTAssertNil(model.start(), "Inspect before enabling the action")
        await model.load().value
        XCTAssertEqual(exporter.exports, 0)
        XCTAssertTrue(model.canStart)
        model.preset = .compact
        let task = try XCTUnwrap(model.start())
        XCTAssertTrue(model.isWorking)
        XCTAssertNil(model.start(), "Double clicks must not start two jobs")
        await task.value
        XCTAssertEqual(exporter.exports, 1)
        XCTAssertEqual(exporter.preset, .compact)
        XCTAssertEqual(model.progress, 1)
        XCTAssertNotNil(model.result)
        XCTAssertNil(library.currentWallpaper)
        XCTAssertEqual(refreshed, 1)
        XCTAssertFalse(model.isWorking)
        XCTAssertFalse(model.canStart)
        model.apply(result.url)
        XCTAssertEqual(library.currentWallpaper?.url, result.url)
        model.apply(source.url)
        XCTAssertEqual(library.currentWallpaper?.url, source.url)
        XCTAssertEqual(library.userInitiated, [true, true])
    }
    func testUnsupportedPresetAndInspectionFailureStayVisible() async {
        exporter.unavailable = [.hevc: "No hardware HEVC"]
        let model = VideoOptimizationModel(source: source, optimizer: exporter, library: library)
        await model.load().value
        model.preset = .hevc
        XCTAssertEqual(model.unavailableReason, "No hardware HEVC")
        XCTAssertNil(model.start())
        XCTAssertFalse(model.canStart)
        model.preset = .compact
        XCTAssertTrue(model.canStart)
        exporter.inspectionError = VideoOptimizationError.unsupported("HDR unsupported")
        let bad = VideoOptimizationModel(source: source, optimizer: exporter, library: library)
        await bad.load().value
        XCTAssertEqual(bad.error, "HDR unsupported")
        XCTAssertFalse(bad.canStart)
    }
    func testCancellationWaitsForCleanupAndAllowsRetry() async throws {
        exporter.waitUntilCancelled = true
        let started = expectation(description: "Conversion entered")
        exporter.started = { started.fulfill() }
        let model = VideoOptimizationModel(source: source, optimizer: exporter, library: library)
        await model.load().value
        let task = try XCTUnwrap(model.start())
        await fulfillment(of: [started], timeout: 2)
        model.cancel()
        XCTAssertTrue(model.isCancelling)
        XCTAssertTrue(model.isWorking, "Keep the job busy until the exporter has cleaned up")
        await task.value
        XCTAssertTrue(exporter.cleanedUp)
        XCTAssertFalse(model.isWorking)
        XCTAssertFalse(model.isCancelling)
        XCTAssertTrue(model.message?.contains("Cancelled") == true)
        XCTAssertNil(model.error)
        XCTAssertNil(model.result)
        XCTAssertTrue(model.canStart)
        exporter.waitUntilCancelled = false
        exporter.started = nil
        await model.start()?.value
        XCTAssertNotNil(model.result)
    }
    func testFailureDoesNotApplyAndMissingSourceCannotBeRestored() async throws {
        exporter.conversionError = VideoOptimizationError.diskSpace(1000)
        let model = VideoOptimizationModel(source: source, optimizer: exporter, library: library)
        await model.load().value
        await model.start()?.value
        XCTAssertTrue(model.error?.contains("disk space") == true)
        XCTAssertFalse(model.isWorking)
        XCTAssertNil(model.result)
        XCTAssertNil(library.currentWallpaper)
        try FileManager.default.removeItem(at: source.url)
        model.apply(source.url)
        XCTAssertTrue(model.error?.contains("no longer") == true)
        XCTAssertNil(library.currentWallpaper)
    }
}

@MainActor
private final class OptimizationExporterSpy: VideoOptimizing {
    var exports = 0
    var preset: VideoOptimizationPreset?
    var unavailable: [VideoOptimizationPreset: String] = [:]
    var inspectionError: Error?
    var conversionError: Error?
    var waitUntilCancelled = false
    var cleanedUp = false
    var started: (() -> Void)?
    let result: OptimizedVideoResult
    init(result: OptimizedVideoResult) { self.result = result }
    func inspect(_ source: URL) async throws -> VideoOptimizationInfo {
        if let inspectionError { throw inspectionError }
        return VideoOptimizationInfo(duration: 1, size: CGSize(width: 640, height: 360), frameRate: 60, sourceBytes: 10, unavailable: unavailable, assumesSDR: false)
    }
    func optimize(_ source: URL, preset: VideoOptimizationPreset, progress: @escaping (Double) -> Void) async throws -> OptimizedVideoResult {
        exports += 1
        self.preset = preset
        progress(0.5)
        started?()
        defer { cleanedUp = true }
        if waitUntilCancelled { try await Task.sleep(nanoseconds: 30_000_000_000) }
        if let conversionError { throw conversionError }
        return result
    }
}

private final class OptimizationLibrarySpy: WallpaperReading, WallpaperWriting {
    var wallpapers: [Wallpaper] = []
    var currentWallpaper: Wallpaper?
    var isPlaying = false
    var userInitiated: [Bool] = []
    func wallpaper(for screen: NSScreen) -> Wallpaper? { currentWallpaper }
    func setWallpaper(_ wallpaper: Wallpaper, userInitiated: Bool) { currentWallpaper = wallpaper; self.userInitiated.append(userInitiated) }
    func setWallpaper(_ wallpaper: Wallpaper, for screen: NSScreen, userInitiated: Bool) { setWallpaper(wallpaper, userInitiated: userInitiated) }
    func togglePlayback() { isPlaying.toggle() }
    func cycleToNextWallpaper() { }
    func importVideo(from sourceURL: URL) async throws -> Wallpaper { Wallpaper(url: sourceURL) }
}
