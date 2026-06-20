import XCTest
@testable import Wallnetic

final class PlaylistManagerTests: XCTestCase {

    // MARK: - Sequential order

    func testSequentialAdvancesByOne() {
        XCTAssertEqual(PlaylistManager.nextSequentialIndex(current: 0, count: 4), 1)
        XCTAssertEqual(PlaylistManager.nextSequentialIndex(current: 2, count: 4), 3)
    }

    func testSequentialWrapsAround() {
        XCTAssertEqual(PlaylistManager.nextSequentialIndex(current: 3, count: 4), 0)
    }

    func testSequentialStartsAtZeroWhenCurrentUnknown() {
        XCTAssertEqual(PlaylistManager.nextSequentialIndex(current: nil, count: 4), 0)
        // Out-of-range current (source changed under us) also restarts at 0.
        XCTAssertEqual(PlaylistManager.nextSequentialIndex(current: 9, count: 4), 0)
    }

    func testSequentialNilForEmptySet() {
        XCTAssertNil(PlaylistManager.nextSequentialIndex(current: nil, count: 0))
        XCTAssertNil(PlaylistManager.nextSequentialIndex(current: 0, count: 0))
    }

    // MARK: - Shuffle candidates

    func testShuffleExcludesCurrentToAvoidImmediateRepeat() {
        let candidates = PlaylistManager.shuffleCandidates(count: 5, current: 2)
        XCTAssertEqual(candidates.sorted(), [0, 1, 3, 4])
        XCTAssertFalse(candidates.contains(2))
    }

    func testShuffleIncludesAllWhenCurrentUnknown() {
        XCTAssertEqual(PlaylistManager.shuffleCandidates(count: 3, current: nil).sorted(), [0, 1, 2])
    }

    func testShuffleSingleItemStaysAvailable() {
        // With one item there's no "other" to pick, so it stays a candidate
        // rather than returning empty (advance() guards count > 1 anyway).
        XCTAssertEqual(PlaylistManager.shuffleCandidates(count: 1, current: 0), [0])
    }

    func testShuffleEmptyForEmptySet() {
        XCTAssertTrue(PlaylistManager.shuffleCandidates(count: 0, current: nil).isEmpty)
    }

    // MARK: - Interval labels

    func testIntervalLabels() {
        XCTAssertEqual(PlaylistManager.intervalLabel(300), "5 minutes")
        XCTAssertEqual(PlaylistManager.intervalLabel(1800), "30 minutes")
        XCTAssertEqual(PlaylistManager.intervalLabel(3600), "1 hour")
        XCTAssertEqual(PlaylistManager.intervalLabel(21600), "6 hours")
        XCTAssertEqual(PlaylistManager.intervalLabel(86400), "Daily")
    }
}
