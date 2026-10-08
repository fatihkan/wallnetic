import XCTest
import AVFoundation
@testable import Wallnetic

@MainActor
final class OnboardingDemoTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suite = "OnboardingDemoTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDownWithError() throws {
        if let defaults, let suite { defaults.removePersistentDomain(forName: suite) }
        if let directory, FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func fixture() throws -> URL {
        let source = directory.appendingPathComponent("AuroraSample.mp4")
        try Data("original sample".utf8).write(to: source)
        return source
    }

    func testSampleInstallsOnceAndSurvivesLibraryIdentityReload() async throws {
        let source = try fixture()
        let library = DemoLibrary(directory: directory.appendingPathComponent("Library"))
        let installer = OnboardingSampleInstaller(library: library, defaults: defaults, source: { source })
        async let a = installer.install()
        async let b = installer.install()
        let (first, second) = try await (a, b)
        XCTAssertEqual(first.url, second.url)
        XCTAssertEqual(library.importCount, 1)
        library.wallpapers = library.wallpapers.map { Wallpaper(url: $0.url) }
        let restored = OnboardingSampleInstaller(library: library, defaults: defaults, source: { source })
        let afterReload = try await restored.install()
        XCTAssertEqual(afterReload.url, first.url)
        XCTAssertEqual(library.importCount, 1)
        XCTAssertNotEqual(first.url, source)
        XCTAssertEqual(try Data(contentsOf: source), Data("original sample".utf8))
    }

    func testModifiedSampleAndOtherUserFilesAreNeverOverwritten() async throws {
        let source = try fixture()
        let library = DemoLibrary(directory: directory.appendingPathComponent("Library"))
        let originalUserFile = try await library.importVideo(from: source)
        let installer = OnboardingSampleInstaller(library: library, defaults: defaults, source: { source })
        let first = try await installer.install()
        XCTAssertNotEqual(first.url, originalUserFile.url)
        try Data("modified by user".utf8).write(to: first.url)
        let replacement = try await installer.install()
        XCTAssertNotEqual(replacement.url, first.url)
        XCTAssertEqual(try Data(contentsOf: first.url), Data("modified by user".utf8))
        XCTAssertEqual(try Data(contentsOf: originalUserFile.url), Data("original sample".utf8))
    }

    func testRemovedSampleCanBeInstalledAgain() async throws {
        let source = try fixture()
        let library = DemoLibrary(directory: directory.appendingPathComponent("Library"))
        let installer = OnboardingSampleInstaller(library: library, defaults: defaults, source: { source })
        let first = try await installer.install()
        try FileManager.default.removeItem(at: first.url)
        library.wallpapers = []
        let next = try await installer.install()
        XCTAssertNotEqual(next.url, first.url)
        XCTAssertEqual(library.importCount, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testMissingAndOversizedSamplesFailWithoutImporting() async throws {
        let library = DemoLibrary(directory: directory)
        let oversized = directory.appendingPathComponent("oversized.mp4")
        try Data(count: OnboardingSampleInstaller.maximumBytes + 1).write(to: oversized)
        for source in [nil, oversized] as [URL?] {
            let installer = OnboardingSampleInstaller(library: library, defaults: defaults, source: { source })
            do { _ = try await installer.install(); XCTFail("Invalid bundled resource must fail") }
            catch { XCTAssertTrue(error is OnboardingDemoError) }
        }
        XCTAssertEqual(library.importCount, 0)
    }

    func testCancellingAnImportThatFinishesLateNeverAppliesOrDuplicates() async throws {
        let wallpaper = Wallpaper(url: try fixture())
        var continuation: CheckedContinuation<Wallpaper, Never>?
        var applies = 0
        let model = OnboardingDemoModel(sample: {
            await withCheckedContinuation { continuation = $0 }
        }, importVideo: { _ in wallpaper }, apply: { _, _ in applies += 1 })
        let operation = try XCTUnwrap(model.trySample(on: 17))
        XCTAssertNil(model.trySample(on: nil), "Double click cannot enqueue a second installation")
        while continuation == nil { await Task.yield() }
        model.cancel()
        continuation?.resume(returning: wallpaper)
        await operation.value
        XCTAssertEqual(applies, 0)
        XCTAssertFalse(model.isWorking)
        XCTAssertNil(model.error)
    }

    func testSampleAndOwnVideoUseCapturedTargetAndReportDisconnectedDisplay() async throws {
        let wallpaper = Wallpaper(url: try fixture())
        var targets: [UInt32?] = []
        let model = OnboardingDemoModel(sample: { wallpaper }, importVideo: { _ in wallpaper },
            apply: { _, target in
                if target == 99 { throw OnboardingDemoError.displayDisconnected }
                targets.append(target)
            })
        await model.trySample(on: nil)?.value
        await model.importFile(wallpaper.url, on: 17)?.value
        await model.trySample(on: 99)?.value
        XCTAssertEqual(targets.count, 2)
        XCTAssertNil(targets[0])
        XCTAssertEqual(targets[1], 17)
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.isWorking)
    }

    func testDisplayPathsPersistWithoutFillingAnIntentionallyEmptyDisplay() {
        let a = URL(fileURLWithPath: "/Library/a.mp4"), b = URL(fileURLWithPath: "/Library/b.mp4")
        let store = DisplayWallpaperAssignments(defaults: defaults)
        store.set(a, for: "screen-a")
        store.set(nil, for: "screen-b")
        store.set(b, for: "screen-c")
        let restored = DisplayWallpaperAssignments(defaults: defaults)
        XCTAssertEqual(restored.selection(for: "screen-a"), .file(a))
        XCTAssertEqual(restored.selection(for: "screen-b"), .empty)
        XCTAssertEqual(restored.selection(for: "new-screen"), .inherit)
        restored.remove(a)
        XCTAssertEqual(restored.selection(for: "screen-a"), .empty)
        XCTAssertEqual(restored.selection(for: "screen-c"), .file(b))
    }

    func testBundledSampleIsSmallPlayableAndHasNoAudio() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "AuroraSample", withExtension: "mp4"))
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        XCTAssertGreaterThan(size, 0)
        XCTAssertLessThan(size, 400 * 1_024, "Keep the size promised in onboarding")
        let asset = AVURLAsset(url: url)
        let playable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertTrue(playable)
        XCTAssertEqual(duration.seconds, 6, accuracy: 0.05)
        let track = try XCTUnwrap(videoTracks.first)
        let sizePixels = try await track.load(.naturalSize)
        XCTAssertEqual(sizePixels, CGSize(width: 1280, height: 720))
        XCTAssertTrue(audioTracks.isEmpty)
    }

    func testUniformApplyAfterTargetedSelectionAndRemovalClearControllerState() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let id = try XCTUnwrap(screen.displayID)
        let controller = DesktopWindowController()
        defer { controller.cleanup() }
        let first = directory.appendingPathComponent("not-loaded-a.mp4")
        let second = directory.appendingPathComponent("not-loaded-b.mp4")
        var statuses: [DisplayPlaybackStatus] = []
        controller.onDisplayStatusesChanged = { statuses = $0 }
        controller.setWallpaper(url: first)
        controller.setWallpaper(url: second, for: screen)
        XCTAssertEqual(controller.wallpaperURL(on: id), second)
        controller.setWallpaper(url: first)
        for screen in NSScreen.screens {
            let screenID = try XCTUnwrap(screen.displayID)
            XCTAssertEqual(controller.wallpaperURL(on: screenID), first)
        }
        controller.clearWallpaper(on: id)
        XCTAssertNil(controller.wallpaperURL(on: id))
        for other in NSScreen.screens where other.displayID != id {
            XCTAssertEqual(controller.wallpaperURL(on: try XCTUnwrap(other.displayID)), first,
                           "Restoring an empty display must not clear another display")
        }
        controller.setWallpaper(url: first)
        XCTAssertEqual(controller.wallpaperURL(on: id), first)
        controller.clearWallpaper(url: first)
        XCTAssertNil(controller.wallpaperURL(on: id))
        XCTAssertFalse(statuses.isEmpty)
        XCTAssertTrue(statuses.allSatisfy { $0.state == .notSet })
    }
}

private final class DemoLibrary: WallpaperReading, WallpaperWriting {
    var wallpapers: [Wallpaper] = []
    var currentWallpaper: Wallpaper?
    var isPlaying = false
    var importCount = 0
    let library: WallpaperLibrary
    init(directory: URL) { library = WallpaperLibrary(directory: directory) }
    func importVideo(from sourceURL: URL) async throws -> Wallpaper {
        let url = try await library.importFile(from: sourceURL, existingWallpapers: wallpapers)
        let wallpaper = Wallpaper(url: url)
        wallpapers.append(wallpaper)
        importCount += 1
        return wallpaper
    }
    func wallpaper(for screen: NSScreen) -> Wallpaper? { currentWallpaper }
    func setWallpaper(_ wallpaper: Wallpaper, userInitiated: Bool) { currentWallpaper = wallpaper }
    func setWallpaper(_ wallpaper: Wallpaper, for screen: NSScreen, userInitiated: Bool) { currentWallpaper = wallpaper }
    func togglePlayback() { isPlaying.toggle() }
    func cycleToNextWallpaper() { currentWallpaper = wallpapers.first }
}
