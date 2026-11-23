import XCTest
@testable import Wallnetic

/// The scaling store uses fresh preferences for every test.
final class WallpaperScalingStoreTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private let a = URL(fileURLWithPath: "/tmp/scaling-a.mp4")
    private let b = URL(fileURLWithPath: "/tmp/scaling-b.mp4")

    override func setUpWithError() throws {
        suite = "WallpaperScalingStoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testFillIsTheDefaultAndAChoiceSurvivesRelaunch() {
        let store = WallpaperScalingStore(defaults: defaults)
        XCTAssertEqual(store.scaling(for: a), .fill)
        store.setScaling(.fitBlurred, for: a)
        XCTAssertEqual(store.scaling(for: a), .fitBlurred)
        XCTAssertEqual(store.scaling(for: b), .fill, "The choice belongs to one wallpaper")
        XCTAssertEqual(WallpaperScalingStore(defaults: defaults).scaling(for: a), .fitBlurred)
    }

    func testGoingBackToFillStoresNothing() {
        let store = WallpaperScalingStore(defaults: defaults)
        store.setScaling(.fitBlurred, for: a)
        store.setScaling(.fill, for: a)
        XCTAssertTrue(store.scalings.isEmpty)
        XCTAssertTrue(WallpaperScalingStore(defaults: defaults).scalings.isEmpty)
    }

    func testRemovedLibraryItemsLoseTheirChoice() {
        let store = WallpaperScalingStore(defaults: defaults)
        store.setScaling(.fitBlurred, for: a)
        store.setScaling(.fitBlurred, for: b)
        store.removeScalings(for: [a])
        XCTAssertEqual(store.scaling(for: a), .fill)
        XCTAssertEqual(store.scaling(for: b), .fitBlurred)
    }

    func testAPathIsMatchedInItsStandardizedForm() {
        let store = WallpaperScalingStore(defaults: defaults)
        store.setScaling(.fitBlurred, for: URL(fileURLWithPath: "/tmp/x/../scaling-a.mp4"))
        XCTAssertEqual(store.scaling(for: a), .fitBlurred)
    }
}
