import XCTest
@testable import Wallnetic

final class FuzzySearchTests: XCTestCase {

    private var manager: WallpaperManager!

    override func setUp() {
        super.setUp()
        manager = WallpaperManager.shared
    }

    // MARK: - Search

    func testEmptyQueryReturnsAll() {
        let results = manager.searchWallpapers(query: "")
        XCTAssertEqual(results.count, manager.wallpapers.count)
    }

    func testWhitespaceQueryReturnsAll() {
        let results = manager.searchWallpapers(query: "   ")
        XCTAssertEqual(results.count, manager.wallpapers.count)
    }

    func testExactMatchScoresHighest() {
        // If any wallpaper name matches exactly, it should be first
        guard let first = manager.wallpapers.first else { return }
        let results = manager.searchWallpapers(query: first.displayName)
        if let topResult = results.first {
            XCTAssertEqual(topResult.id, first.id)
        }
    }

    func testNoMatchReturnsEmpty() {
        let results = manager.searchWallpapers(query: "zzzzxxxxxqqqqqnonexistent12345")
        XCTAssertTrue(results.isEmpty)
    }

    func testPartialMatchFindsResults() {
        guard let first = manager.wallpapers.first else { return }
        let name = first.displayName
        guard name.count >= 3 else { return }

        let partial = String(name.prefix(3))
        let results = manager.searchWallpapers(query: partial)
        XCTAssertFalse(results.isEmpty)
    }

    func testCaseInsensitiveSearch() {
        guard let first = manager.wallpapers.first else { return }
        let upper = first.displayName.uppercased()
        let lower = first.displayName.lowercased()

        let upperResults = manager.searchWallpapers(query: upper)
        let lowerResults = manager.searchWallpapers(query: lower)

        // Both should find the same wallpaper
        XCTAssertEqual(upperResults.first?.id, lowerResults.first?.id)
    }
}
