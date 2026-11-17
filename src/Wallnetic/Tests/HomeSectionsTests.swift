import XCTest
@testable import Wallnetic

final class HomeSectionsTests: XCTestCase {
    private func wallpaper(_ name: String, favorite: Bool = false) -> Wallpaper {
        Wallpaper(url: URL(fileURLWithPath: "/tmp/\(name).mp4"), isFavorite: favorite)
    }

    private func display(_ id: UInt32, hasWallpaper: Bool = true,
                         renderer: RendererPlaybackState = .playing) -> DisplayPlaybackStatus {
        DisplayPlaybackStatus(id: id, displayName: "Display \(id)", hasWallpaper: hasWallpaper,
                              renderer: renderer, reasons: [])
    }

    func testEmptyLibraryShowsDisplaysWithoutWallpaperAndNoRows() {
        let sections = HomeSections.make(
            wallpapers: [],
            displays: [display(1, hasWallpaper: false)],
            wallpaperForDisplay: { _ in UUID() }
        )
        XCTAssertEqual(sections.desktop.count, 1)
        XCTAssertNil(sections.desktop[0].wallpaperID, "A wallpaper outside the library is not shown")
        XCTAssertEqual(sections.desktop[0].statusTitle, "No wallpaper selected")
        XCTAssertTrue(sections.favorites.isEmpty)
        XCTAssertTrue(sections.recent.isEmpty)
        XCTAssertTrue(sections.all.isEmpty)
    }

    func testOneDisplayShowsItsWallpaperAndStatus() {
        let a = wallpaper("a")
        let sections = HomeSections.make(
            wallpapers: [a],
            displays: [display(7)],
            wallpaperForDisplay: { $0 == 7 ? a.id : nil }
        )
        XCTAssertEqual(sections.desktop.map(\.id), [7])
        XCTAssertEqual(sections.desktop[0].wallpaperID, a.id)
        XCTAssertEqual(sections.desktop[0].displayName, "Display 7")
        XCTAssertEqual(sections.desktop[0].statusTitle, "Playing")
    }

    func testTwoDisplaysKeepTheirOwnWallpapersInDisplayOrder() {
        let a = wallpaper("a"), b = wallpaper("b")
        let sections = HomeSections.make(
            wallpapers: [a, b],
            displays: [display(1), display(2, renderer: .paused)],
            wallpaperForDisplay: { $0 == 1 ? a.id : b.id }
        )
        XCTAssertEqual(sections.desktop.map(\.id), [1, 2])
        XCTAssertEqual(sections.desktop.map(\.wallpaperID), [a.id, b.id])
        XCTAssertEqual(sections.desktop[1].statusTitle, "Paused")
    }

    func testFavoritesKeepLibraryOrder() {
        let a = wallpaper("a", favorite: true), b = wallpaper("b"), c = wallpaper("c", favorite: true)
        let sections = HomeSections.make(wallpapers: [a, b, c], displays: [], wallpaperForDisplay: { _ in nil })
        XCTAssertEqual(sections.favorites.map(\.id), [a.id, c.id])
    }

    func testRecentRowDropsWallpapersOlderThanAWeek() {
        let a = wallpaper("a")
        let fresh = HomeSections.make(wallpapers: [a], displays: [], wallpaperForDisplay: { _ in nil })
        XCTAssertEqual(fresh.recent.map(\.id), [a.id])

        let later = Date().addingTimeInterval(HomeSections.recentWindow + 60)
        let stale = HomeSections.make(wallpapers: [a], displays: [], wallpaperForDisplay: { _ in nil }, now: later)
        XCTAssertTrue(stale.recent.isEmpty)
    }

    func testAllRowAppearsOnlyForALargerLibrary() {
        let few = (0..<(HomeSections.minimumForAllRow - 1)).map { wallpaper("few\($0)") }
        let many = (0..<HomeSections.minimumForAllRow).map { wallpaper("many\($0)") }
        XCTAssertTrue(HomeSections.make(wallpapers: few, displays: [], wallpaperForDisplay: { _ in nil }).all.isEmpty)
        XCTAssertEqual(HomeSections.make(wallpapers: many, displays: [], wallpaperForDisplay: { _ in nil }).all.count,
                       HomeSections.minimumForAllRow)
    }
}
