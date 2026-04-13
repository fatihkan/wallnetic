import XCTest
@testable import Wallnetic

final class WallpaperModelTests: XCTestCase {

    // MARK: - Init

    func testInitSetsNameFromURL() {
        let url = URL(fileURLWithPath: "/tmp/My_Wallpaper.mp4")
        let wp = Wallpaper(url: url)

        XCTAssertEqual(wp.name, "My_Wallpaper")
        XCTAssertNil(wp.customTitle)
        XCTAssertEqual(wp.displayName, "My_Wallpaper")
    }

    func testDisplayNamePrefersCustomTitle() {
        var wp = Wallpaper(url: URL(fileURLWithPath: "/tmp/test.mp4"))
        wp.customTitle = "Beautiful Sunset"

        XCTAssertEqual(wp.displayName, "Beautiful Sunset")
        XCTAssertEqual(wp.name, "test")
    }

    func testDisplayNameFallsBackToNameWhenCustomTitleNil() {
        var wp = Wallpaper(url: URL(fileURLWithPath: "/tmp/ocean_waves.mp4"))
        wp.customTitle = nil

        XCTAssertEqual(wp.displayName, "ocean_waves")
    }

    func testDisplayNameFallsBackWhenCustomTitleEmpty() {
        var wp = Wallpaper(url: URL(fileURLWithPath: "/tmp/test.mp4"))
        wp.customTitle = nil // Empty customTitle should show name

        XCTAssertEqual(wp.displayName, "test")
    }

    // MARK: - Equatable

    func testEqualityIncludesCustomTitle() {
        var wp1 = Wallpaper(url: URL(fileURLWithPath: "/tmp/test.mp4"))
        var wp2 = wp1
        wp2.customTitle = "Renamed"

        // Same id but different customTitle → not equal
        XCTAssertNotEqual(wp1, wp2)
    }

    func testEqualityIncludesFavorite() {
        var wp1 = Wallpaper(url: URL(fileURLWithPath: "/tmp/test.mp4"))
        var wp2 = wp1
        wp2.isFavorite = true

        XCTAssertNotEqual(wp1, wp2)
    }

    func testHashConsistentWithEquality() {
        var wp1 = Wallpaper(url: URL(fileURLWithPath: "/tmp/test.mp4"))
        let wp2 = wp1

        // Equal objects must have same hash
        XCTAssertEqual(wp1.hashValue, wp2.hashValue)

        // After mutation, hash should differ
        wp1.customTitle = "Changed"
        XCTAssertNotEqual(wp1.hashValue, wp2.hashValue)
    }

    // MARK: - Formatted Properties

    func testFormattedFileSize() {
        let wp = Wallpaper(url: URL(fileURLWithPath: "/tmp/nonexistent.mp4"))
        // File doesn't exist, size = 0
        XCTAssertEqual(wp.formattedFileSize, "Zero KB")
    }

    func testFormattedDurationNil() {
        let wp = Wallpaper(url: URL(fileURLWithPath: "/tmp/test.mp4"))
        XCTAssertEqual(wp.formattedDuration, "--:--")
    }

    func testFormattedResolutionNil() {
        let wp = Wallpaper(url: URL(fileURLWithPath: "/tmp/test.mp4"))
        XCTAssertEqual(wp.formattedResolution, "Unknown")
    }

    // MARK: - Tags

    func testTagsEmptyByDefault() {
        let wp = Wallpaper(url: URL(fileURLWithPath: "/tmp/test.mp4"))
        XCTAssertTrue(wp.tags.isEmpty)
    }

    func testTagsMutation() {
        var wp = Wallpaper(url: URL(fileURLWithPath: "/tmp/test.mp4"))
        wp.tags = ["nature", "4k", "landscape"]
        XCTAssertEqual(wp.tags.count, 3)
        XCTAssertTrue(wp.tags.contains("nature"))
    }
}
