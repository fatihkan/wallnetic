import Darwin
import XCTest
@testable import Wallnetic

final class LibraryReviewTests: XCTestCase {
    func testImportGateKeepsSuspendingOperationsExclusive() async throws {
        let gate = ImportGate()
        let probe = ImportConcurrencyProbe()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<24 {
                group.addTask {
                    try await gate.run {
                        await probe.enter()
                        try await Task.sleep(nanoseconds: 2_000_000)
                        await probe.leave()
                    }
                }
            }
            try await group.waitForAll()
        }
        let peak = await probe.peak
        let completed = await probe.completed
        XCTAssertEqual(peak, 1, "Imports must remain exclusive across await points")
        XCTAssertEqual(completed, 24)
    }

    func testImportGateReleasesPermitAfterFailure() async throws {
        let gate = ImportGate()
        do {
            try await gate.run { throw WallpaperImportError.unsupportedFile }
            XCTFail("Expected import failure")
        } catch WallpaperImportError.unsupportedFile {
            // The next operation must still acquire the permit.
        }
        let value = try await gate.run { 42 }
        XCTAssertEqual(value, 42)
    }

    func testCancelledImportDoesNotExecuteAndReleasesPermit() async throws {
        let gate = ImportGate()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await gate.run { 42 }
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled import must not execute")
        } catch is CancellationError {
            // Expected.
        }
        let value = try await gate.run { 7 }
        XCTAssertEqual(value, 7)
    }

    @MainActor
    func testNonPositiveImportConcurrencyDoesNotSilentlyDropInputs() async {
        let source = URL(fileURLWithPath: "/tmp/unsupported-wallnetic-review.txt")
        for limit in [0, -1] {
            let results = await WallpaperManager.shared.importVideos(from: [source], maxInflight: limit)
            XCTAssertEqual(results.count, 1)
            guard case .failure(let error) = results.first,
                  case WallpaperImportError.unsupportedFile = error else {
                XCTFail("Each input must produce a result even when the concurrency limit is invalid")
                continue
            }
        }
    }

    func testNativeImportsPreserveExtensionAndSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = WallpaperLibrary(directory: root.appendingPathComponent("Library"))
        let bytes = Data([0, 1, 2, 3])

        for ext in ["MOV", "m4v", "mp4", "hevc"] {
            let source = root.appendingPathComponent("clip.\(ext)")
            try bytes.write(to: source)
            let destination = try await library.importFile(from: source, existingWallpapers: [])
            XCTAssertEqual(destination.pathExtension, ext.lowercased())
            XCTAssertEqual(try Data(contentsOf: destination), bytes)
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
            XCTAssertTrue(library.isVideoFile(destination))
        }
    }

    func testImportRejectsUnsupportedFilesAndDirectories() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = WallpaperLibrary(directory: root.appendingPathComponent("Library"))
        let directory = root.appendingPathComponent("folder.mp4")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = root.appendingPathComponent("notes.txt")
        try Data("not a wallpaper".utf8).write(to: text)

        for source in [directory, text] {
            do {
                _ = try await library.importFile(from: source, existingWallpapers: [])
                XCTFail("Unsupported input should not be copied into the library")
            } catch WallpaperImportError.unsupportedFile {
                // Expected.
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Library").path))
    }

    func testDuplicateImportLeavesExistingFileIntact() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = WallpaperLibrary(directory: root.appendingPathComponent("Library"))
        let source = root.appendingPathComponent("clip.mov")
        let bytes = Data([0, 1, 2, 3])
        try bytes.write(to: source)
        let destination = try await library.importFile(from: source, existingWallpapers: [])
        do {
            _ = try await library.importFile(from: source, existingWallpapers: [Wallpaper(url: destination)])
            XCTFail("Expected duplicate rejection")
        } catch WallpaperImportError.duplicate {
            // Expected.
        }
        XCTAssertEqual(try Data(contentsOf: destination), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.libraryURL.path).count, 1)
    }

    func testNavigationUsesVisibleOrderAndWrapsInBothDirections() {
        let wallpapers = ["c", "a", "b"].map { Wallpaper(url: URL(fileURLWithPath: "/tmp/\($0).mp4")) }
        XCTAssertEqual(WallpaperBrowsing.adjacent(in: wallpapers, currentID: wallpapers[0].id, backwards: true)?.id, wallpapers[2].id)
        XCTAssertEqual(WallpaperBrowsing.adjacent(in: wallpapers, currentID: wallpapers[2].id, backwards: false)?.id, wallpapers[0].id)
        XCTAssertEqual(WallpaperBrowsing.adjacent(in: wallpapers, currentID: wallpapers[1].id, backwards: true)?.id, wallpapers[0].id)
        XCTAssertEqual(WallpaperBrowsing.adjacent(in: wallpapers, currentID: wallpapers[1].id, backwards: false)?.id, wallpapers[2].id)
    }

    func testNavigationHandlesEmptySingleAndFilteredOutCurrentWallpaper() {
        let wallpaper = Wallpaper(url: URL(fileURLWithPath: "/tmp/a.mp4"))
        XCTAssertNil(WallpaperBrowsing.adjacent(in: [], currentID: nil, backwards: true))
        for backwards in [true, false] {
            XCTAssertEqual(WallpaperBrowsing.adjacent(in: [wallpaper], currentID: wallpaper.id, backwards: backwards)?.id, wallpaper.id)
            XCTAssertEqual(WallpaperBrowsing.adjacent(in: [wallpaper], currentID: UUID(), backwards: backwards)?.id, wallpaper.id)
        }
    }

    func testInvalidMetadataFormatsWithoutIntegerConversionTraps() {
        var wallpaper = Wallpaper(url: URL(fileURLWithPath: "/tmp/a.mp4"))
        for duration in [Double.nan, .infinity, -.infinity, -1, Double(Int.max)] {
            wallpaper.duration = duration
            XCTAssertEqual(wallpaper.formattedDuration, "--:--")
        }
        for dimension in [CGFloat.nan, .infinity, -.infinity, -1, 0, CGFloat(Int.max)] {
            wallpaper.resolution = CGSize(width: dimension, height: 1080)
            XCTAssertEqual(wallpaper.formattedResolution, "Unknown")
            wallpaper.resolution = CGSize(width: 1920, height: dimension)
            XCTAssertEqual(wallpaper.formattedResolution, "Unknown")
        }
        wallpaper.duration = 125.9
        wallpaper.resolution = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(wallpaper.formattedDuration, "2:05")
        XCTAssertEqual(wallpaper.formattedResolution, "1920×1080")
    }
}

final class DownloadFilenameTests: XCTestCase {
    private var root: URL!
    private var library: WallpaperLibrary!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let physical = try XCTUnwrap(realpath(root.path, nil))
        defer { free(physical) }
        root = URL(fileURLWithPath: String(cString: physical), isDirectory: true)
        library = WallpaperLibrary(directory: root.appendingPathComponent("Library"))
    }

    override func tearDownWithError() throws {
        library = nil
        if let root { try FileManager.default.removeItem(at: root) }
    }

    private func source(fileName: String? = nil, bytes: Data = Data([1, 2, 3])) throws -> URL {
        let url = root.appendingPathComponent(fileName ?? UUID().uuidString + ".mp4")
        try bytes.write(to: url)
        return url
    }

    func testReadableFilenameUsesActualMediaExtensionAndPreservesSource() async throws {
        for ext in ["mp4", "MOV", "m4v", "hevc"] {
            let input = try source(fileName: UUID().uuidString + "." + ext)
            let destination = try await library.importFile(from: input, existingWallpapers: [], preferredName: "Ocean Sunset")
            XCTAssertEqual(destination.lastPathComponent, "Ocean Sunset." + ext.lowercased())
            XCTAssertEqual(try Data(contentsOf: input), Data([1, 2, 3]))
            XCTAssertEqual(try Data(contentsOf: destination), Data([1, 2, 3]))
            XCTAssertTrue(library.isVideoFile(destination))
        }
    }

    func testRepeatedTitlesKeepDistinctSameSizeDownloadsWithoutOverwriting() async throws {
        let first = try await library.importFile(from: source(), existingWallpapers: [], preferredName: "Shared")
        // The new source's filename and size even match the previous copy.
        // A common download title must not incorrectly trigger local deduplication.
        let input = try source(fileName: "Shared.mp4", bytes: Data([4, 5, 6]))
        let second = try await library.importFile(from: input, existingWallpapers: [Wallpaper(url: first)], preferredName: "Shared")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.lastPathComponent, "Shared.mp4")
        XCTAssertTrue(second.lastPathComponent.hasPrefix("Shared ("))
        XCTAssertEqual(second.pathExtension, "mp4")
        XCTAssertEqual(try Data(contentsOf: first), Data([1, 2, 3]))
        XCTAssertEqual(try Data(contentsOf: second), Data([4, 5, 6]))
        XCTAssertEqual(try Data(contentsOf: input), Data([4, 5, 6]))
    }

    func testUnsafeTitlesRemainVisibleSingleComponentsInsideLibrary() async throws {
        let titles = ["../../escape/owned\\name: <movie> | ? *", "/absolute/escape", ".hidden",
                      "evil.app", " \u{0000}\u{202E}Ocean\nSunset ", "$(touch injected)"]
        for title in titles {
            let destination = try await library.importFile(from: source(), existingWallpapers: [], preferredName: title)
            XCTAssertEqual(destination.deletingLastPathComponent().standardizedFileURL.path, library.libraryURL.standardizedFileURL.path)
            XCTAssertEqual(destination.pathExtension, "mp4")
            XCTAssertFalse(destination.lastPathComponent.hasPrefix("."))
            XCTAssertNil(destination.lastPathComponent.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\:*?\"<>|")))
            XCTAssertEqual(try Data(contentsOf: destination), Data([1, 2, 3]))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("injected").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escape").path))
    }

    func testUnusableTitlesKeepGeneratedFilenameFallback() async throws {
        for title in [nil, "", " \n\t ", "... / \\ : * ? < > |", "\u{0000}\u{202E}", String(repeating: "x", count: 4097)] as [String?] {
            let input = try source()
            let destination = try await library.importFile(from: input, existingWallpapers: [], preferredName: title)
            XCTAssertEqual(destination.lastPathComponent, input.lastPathComponent)
            XCTAssertEqual(try Data(contentsOf: input), Data([1, 2, 3]))
        }
    }

    func testLongUnicodeTitlesFitFilesystemLimitIncludingCollisionSuffix() async throws {
        for title in [String(repeating: "🌅", count: 160), String(repeating: "é", count: 160),
                      String(repeating: "👩‍🚀", count: 160)] {
            let first = try await library.importFile(from: source(), existingWallpapers: [], preferredName: title)
            let second = try await library.importFile(from: source(), existingWallpapers: [], preferredName: title)
            XCTAssertNotEqual(first, second)
            for destination in [first, second] {
                XCTAssertLessThanOrEqual(destination.lastPathComponent.decomposedStringWithCanonicalMapping.utf8.count, 255)
                XCTAssertTrue(destination.lastPathComponent.hasPrefix(String(try XCTUnwrap(title.first))))
                XCTAssertEqual(try Data(contentsOf: destination), Data([1, 2, 3]))
            }
        }
        let input = try source()
        let oversizedCharacter = "e" + String(repeating: "\u{0301}", count: 500)
        let destination = try await library.importFile(from: input, existingWallpapers: [], preferredName: oversizedCharacter)
        XCTAssertEqual(destination.lastPathComponent, input.lastPathComponent)
    }

    func testCollisionsPreserveDirectoriesAndSymbolicLinkTargets() async throws {
        let directory = library.libraryURL.appendingPathComponent("Directory.mp4", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let marker = directory.appendingPathComponent("keep.txt")
        try Data([9]).write(to: marker)
        let outside = root.appendingPathComponent("outside.mp4")
        try Data([8]).write(to: outside)
        let missing = root.appendingPathComponent("missing.mp4")
        for (name, target) in [("Link", outside), ("Dangling", missing)] {
            try FileManager.default.createSymbolicLink(at: library.libraryURL.appendingPathComponent(name + ".mp4"),
                                                      withDestinationURL: target)
        }
        for name in ["Directory", "Link", "Dangling"] {
            let destination = try await library.importFile(from: source(), existingWallpapers: [], preferredName: name)
            XCTAssertTrue(destination.lastPathComponent.hasPrefix(name + " ("))
            XCTAssertEqual(try Data(contentsOf: destination), Data([1, 2, 3]))
        }
        XCTAssertEqual(try Data(contentsOf: marker), Data([9]))
        XCTAssertEqual(try Data(contentsOf: outside), Data([8]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: library.libraryURL.appendingPathComponent("Link.mp4").path), outside.path)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: library.libraryURL.appendingPathComponent("Dangling.mp4").path), missing.path)
    }
}

private actor ImportConcurrencyProbe {
    private var active = 0
    private(set) var peak = 0
    private(set) var completed = 0

    func enter() {
        active += 1
        peak = max(peak, active)
    }

    func leave() {
        active -= 1
        completed += 1
    }
}
