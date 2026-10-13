import Darwin
import XCTest
@testable import Wallnetic

/// Metadata persistence uses fresh preferences and files for every test. Never
/// reset the shared store: a signed test host can see the user's real library.
final class WallpaperMetadataStoreTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var store: WallpaperMetadataStore!
    private var root: URL!

    override func setUpWithError() throws {
        suite = "WallpaperMetadataStoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        store = WallpaperMetadataStore(defaults: defaults)
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Directory enumeration can return /private/var for a /var temporary
        // URL. Use one physical fixture path for import and rescan metadata.
        let physicalPath = try XCTUnwrap(realpath(root.path, nil))
        defer { free(physicalPath) }
        root = URL(fileURLWithPath: String(cString: physicalPath), isDirectory: true)
    }

    override func tearDownWithError() throws {
        store = nil
        defaults.removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: root)
    }

    private func wallpaper() -> Wallpaper {
        Wallpaper(url: root.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4"))
    }

    func testCustomTitlesRoundTrip() {
        let titles = ["/tmp/a.mp4": "Sunset", "/tmp/b.mp4": "Ocean"]
        store.customTitles = titles
        XCTAssertEqual(WallpaperMetadataStore(defaults: defaults).customTitles, titles)
    }

    func testSavedColorsRoundTrip() {
        let colors = ["/tmp/a.mp4": "#FF8800"]
        store.savedColors = colors
        XCTAssertEqual(WallpaperMetadataStore(defaults: defaults).savedColors, colors)
    }

    func testTagsRoundTrip() {
        let tags = ["/tmp/a.mp4": ["nature", "sunset"]]
        store.savedTags = tags
        XCTAssertEqual(WallpaperMetadataStore(defaults: defaults).savedTags, tags)
    }

    func testDownloadedTitleSurvivesRealImportRescanAndSearchIndexRebuild() async throws {
        let source = root.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        let bytes = Data("test import payload".utf8)
        try bytes.write(to: source)
        let libraryURL = root.appendingPathComponent("Library")
        let library = WallpaperLibrary(directory: libraryURL)
        let destination = try await library.importFile(from: source, existingWallpapers: [])
        var imported = Wallpaper(url: destination)
        store.applyImportedTitle("Ocean at sunset", to: &imported)

        XCTAssertEqual(imported.displayName, "Ocean at sunset")
        XCTAssertEqual(destination.lastPathComponent, source.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        let restored = WallpaperMetadataStore(defaults: defaults)
        var reloaded = library.loadAll(favoritePaths: [])
        restored.applyCustomTitles(to: &reloaded)
        let item = try XCTUnwrap(reloaded.first)
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(item.displayName, "Ocean at sunset")
        XCTAssertEqual(item.url, destination)
        let cache = WallpaperMetadataCache.makeInMemoryForTesting()
        cache.replaceAll(with: reloaded)
        XCTAssertEqual(cache.searchIds(query: "Ocean at sunset"), [item.id])
    }

    func testExistingUserTitleAndOtherMetadataArePreserved() {
        var item = wallpaper()
        store.customTitles = [item.url.path: "My chosen title", "/other.mp4": "Other title"]
        store.savedTags = [item.url.path: ["favorite tag"]]
        store.savedColors = [item.url.path: "#FF8800"]
        store.favoritePaths = [item.url.path]
        store.applyImportedTitle("Server title", to: &item)
        XCTAssertEqual(item.displayName, "My chosen title")
        let restored = WallpaperMetadataStore(defaults: defaults)
        XCTAssertEqual(restored.customTitles, [item.url.path: "My chosen title", "/other.mp4": "Other title"])
        XCTAssertEqual(restored.savedTags[item.url.path], ["favorite tag"])
        XCTAssertEqual(restored.savedColors[item.url.path], "#FF8800")
        XCTAssertEqual(restored.favoritePaths, [item.url.path])
    }

    func testTitleEditedAfterImportSurvivesAnotherSuggestionAndRelaunch() {
        var item = wallpaper()
        store.applyImportedTitle("Downloaded title", to: &item)
        item.customTitle = "User edit"
        store.saveCustomTitles(from: [item])
        let restored = WallpaperMetadataStore(defaults: defaults)
        var reloaded = Wallpaper(url: item.url)
        restored.applyImportedTitle("Another server title", to: &reloaded)
        XCTAssertEqual(reloaded.displayName, "User edit")
        XCTAssertEqual(restored.customTitles[item.url.path], "User edit")
    }

    func testMissingBlankControlOnlyAndOversizedSuggestionsKeepFilenameFallback() {
        for suggestion in [nil, "", " \n\t ", "\u{0000}\u{0007}\u{061C}\u{200E}\u{200F}\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}", String(repeating: "a", count: 4097)] as [String?] {
            var item = wallpaper()
            store.applyImportedTitle(suggestion, to: &item)
            XCTAssertNil(item.customTitle)
            XCTAssertEqual(item.displayName, item.name)
            XCTAssertNil(store.customTitles[item.url.path])
        }
    }

    func testExternalTitleUsesBoundedPlainTextWithoutRenamingAnyFile() throws {
        var item = wallpaper()
        let url = item.url
        try Data("unchanged".utf8).write(to: url)
        store.applyImportedTitle("  ../../Ocean\n\tGökyüzü 👩‍🚀\u{0000}\u{202E}\u{2066}  ", to: &item)
        XCTAssertEqual(item.displayName, "../../Ocean Gökyüzü 👩‍🚀")
        XCTAssertEqual(item.url, url)
        XCTAssertEqual(try Data(contentsOf: url), Data("unchanged".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [url.lastPathComponent])

        var longTitle = wallpaper()
        store.applyImportedTitle(String(repeating: "🌅", count: 200), to: &longTitle)
        XCTAssertEqual(longTitle.customTitle, String(repeating: "🌅", count: 160))
    }

    func testIdenticalDisplayNamesRemainIndependentAndDoNotRenameHistoricalItems() {
        var first = wallpaper(), second = wallpaper()
        let historical = wallpaper()
        store.applyImportedTitle("Same title", to: &first)
        store.applyImportedTitle("Same title", to: &second)
        XCTAssertNotEqual(first.url, second.url)
        XCTAssertEqual(first.displayName, second.displayName)
        var reloaded = [Wallpaper(url: first.url), Wallpaper(url: second.url), historical]
        WallpaperMetadataStore(defaults: defaults).applyCustomTitles(to: &reloaded)
        XCTAssertEqual(reloaded.map(\.displayName), ["Same title", "Same title", historical.name])
        XCTAssertEqual(store.customTitles.count, 2)
    }
}
