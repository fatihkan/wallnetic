import XCTest
@testable import Wallnetic

/// SQLite metadata cache (#115). Uses an in-memory database so tests do
/// not touch the user's Application Support directory.
final class WallpaperMetadataCacheTests: XCTestCase {
    private var cache: WallpaperMetadataCache!

    override func setUp() {
        super.setUp()
        cache = WallpaperMetadataCache.makeInMemoryForTesting()
    }

    override func tearDown() {
        cache = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeWallpaper(name: String, favorite: Bool = false, tags: [String] = [], color: String? = nil) -> Wallpaper {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("wallpaper-cache-test-\(UUID().uuidString)-\(name).mp4")
        try? Data().write(to: tmp)
        var wp = Wallpaper(url: tmp, isFavorite: favorite)
        wp.tags = tags
        wp.dominantColorHex = color
        return wp
    }

    // MARK: - Tests

    func test_upsert_then_count_increments() {
        let wp = makeWallpaper(name: "sunrise")
        cache.upsert(wp)

        // queue is async; flush by querying (search waits on the queue too)
        _ = cache.searchIds(query: "sunrise")
        XCTAssertEqual(cache.count(), 1)
    }

    func test_upsert_replaces_existing_row_on_same_id() {
        let wp = makeWallpaper(name: "ocean", tags: ["blue"])
        cache.upsert(wp)
        cache.upsert(wp)
        _ = cache.searchIds(query: "ocean")
        XCTAssertEqual(cache.count(), 1, "Upserting the same wallpaper twice must not create duplicates.")
    }

    func test_search_matches_name_substring_and_tags() {
        let a = makeWallpaper(name: "mountain-sunrise", tags: ["nature"])
        let b = makeWallpaper(name: "city-skyline", tags: ["urban", "sunrise-special"])
        let c = makeWallpaper(name: "ocean-depths", tags: ["nature"])
        cache.upsert(a)
        cache.upsert(b)
        cache.upsert(c)

        let hits = cache.searchIds(query: "sunrise")
        XCTAssertTrue(hits.contains(a.id), "Name-substring hit expected.")
        XCTAssertTrue(hits.contains(b.id), "Tag-substring hit expected.")
        XCTAssertFalse(hits.contains(c.id), "Non-matching row must be excluded.")
    }

    func test_search_empty_query_returns_empty() {
        cache.upsert(makeWallpaper(name: "anything"))
        XCTAssertEqual(cache.searchIds(query: "  ").count, 0)
        XCTAssertEqual(cache.searchIds(query: "").count, 0)
    }

    func test_delete_removes_row() {
        let wp = makeWallpaper(name: "to-delete")
        cache.upsert(wp)
        _ = cache.searchIds(query: "to-delete")
        XCTAssertEqual(cache.count(), 1)

        cache.delete(id: wp.id)
        _ = cache.searchIds(query: "to-delete")
        XCTAssertEqual(cache.count(), 0)
    }

    func test_replaceAll_drops_stale_rows() {
        let a = makeWallpaper(name: "old-a")
        let b = makeWallpaper(name: "old-b")
        cache.upsert(a)
        cache.upsert(b)
        _ = cache.searchIds(query: "old")
        XCTAssertEqual(cache.count(), 2)

        let c = makeWallpaper(name: "fresh-c")
        cache.replaceAll(with: [c])
        _ = cache.searchIds(query: "fresh")
        XCTAssertEqual(cache.count(), 1)
        XCTAssertEqual(cache.searchIds(query: "fresh"), [c.id])
        XCTAssertEqual(cache.searchIds(query: "old"), [])
    }

    func test_idsByColorCategory_filters_by_dominant_color() {
        let red = makeWallpaper(name: "red-one", color: "#E63946")
        let blue = makeWallpaper(name: "blue-one", color: "#1D3557")
        cache.upsert(red)
        cache.upsert(blue)
        _ = cache.searchIds(query: "one")

        let reds = cache.idsByColorCategory(.red)
        XCTAssertTrue(reds.contains(red.id))
        XCTAssertFalse(reds.contains(blue.id))
    }
}
