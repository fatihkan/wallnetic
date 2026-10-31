import XCTest
@testable import Wallnetic

final class WallpaperVisibilityPolicyTests: XCTestCase {

    // MARK: - Overlay visibility

    /// Showing the overlay before a frame exists is the launch black screen.
    func testOverlayHiddenUntilFirstFrame() {
        XCTAssertFalse(WallpaperVisibilityPolicy.shouldShowOverlay(hasPresentedFrame: false))
    }

    /// Once a frame exists the overlay stays up across operations/reloads
    /// so the previous frame remains visible instead of a black hole.
    func testOverlayStaysUpAfterFirstFrame() {
        XCTAssertTrue(WallpaperVisibilityPolicy.shouldShowOverlay(hasPresentedFrame: true))
    }

    // MARK: - Playback smoothness (stutter)

    func testPlayNotReissuedAtRateOne() {
        XCTAssertFalse(WallpaperPlaybackPolicy.shouldIssuePlay(currentRate: 1))
        XCTAssertTrue(WallpaperPlaybackPolicy.shouldIssuePlay(currentRate: 0))
    }

    /// A drifting rate (stalling-minimization) must not call `play()` —
    /// that restarts the buffer. It should be pinned back to 1.0 instead.
    func testDriftingRateIsCorrectedNotReplayed() {
        XCTAssertFalse(WallpaperPlaybackPolicy.shouldIssuePlay(currentRate: 0.7))
        XCTAssertTrue(WallpaperPlaybackPolicy.shouldCorrectRate(
            currentRate: 0.7, intendedToPlay: true
        ))
        XCTAssertFalse(WallpaperPlaybackPolicy.shouldCorrectRate(
            currentRate: 1, intendedToPlay: true
        ))
        XCTAssertFalse(WallpaperPlaybackPolicy.shouldCorrectRate(
            currentRate: 0.7, intendedToPlay: false
        ))
    }

    /// Closing or backgrounding a windowed app must not stop the wallpaper.
    func testKeepPresentingWhenAppResignsActive() {
        XCTAssertTrue(WallpaperPlaybackPolicy.shouldKeepPresentingWhileInactive(
            intendedToPlay: true
        ))
        XCTAssertFalse(WallpaperPlaybackPolicy.shouldKeepPresentingWhileInactive(
            intendedToPlay: false
        ))
    }
}
