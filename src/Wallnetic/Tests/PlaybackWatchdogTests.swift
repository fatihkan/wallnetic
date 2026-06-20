import XCTest
@testable import Wallnetic

final class PlaybackWatchdogTests: XCTestCase {

    // MARK: - Real stall

    func testFrozenWhenClockDoesNotAdvanceWhilePlaying() {
        XCTAssertTrue(PlaybackWatchdog.isFrozen(
            previous: 12.5,
            current: 12.5,
            intendedToPlay: true,
            shouldBePaused: false
        ))
    }

    func testNotFrozenWhenClockAdvances() {
        XCTAssertFalse(PlaybackWatchdog.isFrozen(
            previous: 12.5,
            current: 13.6,
            intendedToPlay: true,
            shouldBePaused: false
        ))
    }

    // MARK: - Never fight an intentional pause

    func testNotFrozenWhenNotIntendedToPlay() {
        // Same clock, but the controller isn't trying to play — not a stall.
        XCTAssertFalse(PlaybackWatchdog.isFrozen(
            previous: 12.5,
            current: 12.5,
            intendedToPlay: false,
            shouldBePaused: false
        ))
    }

    func testNotFrozenWhenSystemShouldBePaused() {
        // PowerManager deliberately paused (battery / fullscreen / sleep);
        // a non-advancing clock is expected, not a stall.
        XCTAssertFalse(PlaybackWatchdog.isFrozen(
            previous: 12.5,
            current: 12.5,
            intendedToPlay: true,
            shouldBePaused: true
        ))
    }

    // MARK: - Unknown clock is never a stall

    func testNotFrozenWhenNoPreviousSample() {
        XCTAssertFalse(PlaybackWatchdog.isFrozen(
            previous: nil,
            current: 12.5,
            intendedToPlay: true,
            shouldBePaused: false
        ))
    }

    func testNotFrozenWhenNoCurrentSample() {
        // No player loaded (e.g. a still image) — never a stall.
        XCTAssertFalse(PlaybackWatchdog.isFrozen(
            previous: 12.5,
            current: nil,
            intendedToPlay: true,
            shouldBePaused: false
        ))
    }
}
