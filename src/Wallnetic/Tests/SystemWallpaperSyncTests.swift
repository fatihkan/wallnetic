import XCTest
@testable import Wallnetic

final class SystemWallpaperSyncTests: XCTestCase {

    // MARK: - Frame Filename

    func testFrameFileNameIsStable() {
        let url = URL(fileURLWithPath: "/Users/test/Movies/ocean.mp4")
        XCTAssertEqual(
            SystemWallpaperSync.frameFileName(for: url),
            SystemWallpaperSync.frameFileName(for: url)
        )
    }

    func testFrameFileNameDiffersPerPath() {
        let a = URL(fileURLWithPath: "/Users/test/Movies/ocean.mp4")
        let b = URL(fileURLWithPath: "/Users/test/Movies/forest.mp4")
        XCTAssertNotEqual(
            SystemWallpaperSync.frameFileName(for: a),
            SystemWallpaperSync.frameFileName(for: b)
        )
    }

    func testFrameFileNameFormat() {
        let name = SystemWallpaperSync.frameFileName(
            for: URL(fileURLWithPath: "/tmp/clip.mov")
        )
        XCTAssertTrue(name.hasPrefix("frame-"))
        XCTAssertTrue(name.hasSuffix(".jpg"))
        // "frame-" + 16 hex chars + ".jpg"
        XCTAssertEqual(name.count, 26)
    }

    // MARK: - Frame Time

    func testFrameTimeZeroForInvalidDurations() {
        XCTAssertEqual(SystemWallpaperSync.frameTime(forDuration: 0), 0)
        XCTAssertEqual(SystemWallpaperSync.frameTime(forDuration: -5), 0)
        XCTAssertEqual(SystemWallpaperSync.frameTime(forDuration: .nan), 0)
        XCTAssertEqual(SystemWallpaperSync.frameTime(forDuration: .infinity), 0)
    }

    func testFrameTimeSkipsFadeInOnShortVideos() {
        // 10% of a 2s clip is 0.2s — floor lifts it to 0.5s
        XCTAssertEqual(SystemWallpaperSync.frameTime(forDuration: 2), 0.5)
    }

    func testFrameTimeNeverExceedsDuration() {
        // Clip shorter than the 0.5s floor clamps to its own duration
        XCTAssertEqual(SystemWallpaperSync.frameTime(forDuration: 0.3), 0.3)
    }

    func testFrameTimeCapsLongVideos() {
        XCTAssertEqual(SystemWallpaperSync.frameTime(forDuration: 120), 3.0)
    }

    func testFrameTimeMidRangeUsesTenPercent() {
        XCTAssertEqual(SystemWallpaperSync.frameTime(forDuration: 8), 0.8, accuracy: 0.0001)
    }

    // MARK: - Originals JSON

    func testOriginalsRoundTrip() {
        let originals = [
            "Built-in Display": "/System/Library/Desktop Pictures/Sonoma.heic",
            "LG Ultra HD": "/Users/test/Pictures/photo.jpg"
        ]
        let json = SystemWallpaperSync.encodeOriginals(originals)
        XCTAssertEqual(SystemWallpaperSync.decodeOriginals(json), originals)
    }

    func testDecodeOriginalsToleratesGarbage() {
        XCTAssertEqual(SystemWallpaperSync.decodeOriginals("not json"), [:])
        XCTAssertEqual(SystemWallpaperSync.decodeOriginals(""), [:])
        XCTAssertEqual(SystemWallpaperSync.decodeOriginals("[1,2,3]"), [:])
    }

    func testEncodeOriginalsEmpty() {
        XCTAssertEqual(SystemWallpaperSync.encodeOriginals([:]), "{}")
    }

    // MARK: - Frame Cache Cleanup

    func testCleanupKeepsNewestFiles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SystemWallpaperSyncTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Five files with strictly increasing modification dates
        let base = Date(timeIntervalSinceNow: -3600)
        for i in 0..<5 {
            let file = dir.appendingPathComponent("frame-\(i).jpg")
            try Data("x".utf8).write(to: file)
            try FileManager.default.setAttributes(
                [.modificationDate: base.addingTimeInterval(Double(i) * 60)],
                ofItemAtPath: file.path
            )
        }

        SystemWallpaperSync.cleanupFrames(in: dir, keepingNewest: 2)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        XCTAssertEqual(remaining, ["frame-3.jpg", "frame-4.jpg"])
    }

    func testCleanupNoopUnderLimit() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SystemWallpaperSyncTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data("x".utf8).write(to: dir.appendingPathComponent("frame-a.jpg"))
        try Data("x".utf8).write(to: dir.appendingPathComponent("frame-b.jpg"))

        SystemWallpaperSync.cleanupFrames(in: dir, keepingNewest: 8)

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 2)
    }

    func testCleanupToleratesMissingDirectory() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString)")
        // Must not crash or create the directory
        SystemWallpaperSync.cleanupFrames(in: missing, keepingNewest: 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    // MARK: - Frames Directory

    func testFramesDirectoryIsAppScoped() {
        let dir = SystemWallpaperSync.framesDirectory()
        XCTAssertTrue(dir.path.contains("Wallnetic/SystemWallpaper"))
    }
}
