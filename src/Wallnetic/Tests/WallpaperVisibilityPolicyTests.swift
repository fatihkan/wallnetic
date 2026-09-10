import XCTest
@testable import Wallnetic

final class WallpaperVisibilityPolicyTests: XCTestCase {

    // MARK: - The black-desktop cases these tests exist for

    /// Occlusion must not pause an empty renderer. That combination is an
    /// opaque black window covering the real wallpaper with nothing to show
    /// and no watchdog recovery (the watchdog stands down while paused).
    func testOcclusionDoesNotPauseBeforeFirstFrame() {
        XCTAssertFalse(WallpaperVisibilityPolicy.shouldSuspendDecode(
            intendedToPlay: true,
            windowReportsVisible: false,
            hasPresentedFrame: false,
            fullscreenAppCoversDisplay: true
        ))
        XCTAssertTrue(WallpaperVisibilityPolicy.shouldKeepDecoding(
            intendedToPlay: true,
            windowReportsVisible: false,
            hasPresentedFrame: false,
            fullscreenAppCoversDisplay: true
        ))
    }

    /// A fullscreen cover *with* a frame on screen may suspend decode.
    func testFullscreenOcclusionPausesOnceAFrameExists() {
        XCTAssertTrue(WallpaperVisibilityPolicy.shouldSuspendDecode(
            intendedToPlay: true,
            windowReportsVisible: false,
            hasPresentedFrame: true,
            fullscreenAppCoversDisplay: true
        ))
        XCTAssertFalse(WallpaperVisibilityPolicy.shouldKeepDecoding(
            intendedToPlay: true,
            windowReportsVisible: false,
            hasPresentedFrame: true,
            fullscreenAppCoversDisplay: true
        ))
    }

    /// Windowed foreground app: never pause, even if occlusion says hidden.
    /// That combination is the brief freeze / rate wobble / keyframe rollback
    /// around a normal (non-fullscreen) app.
    func testWindowedForegroundAppNeverPausesDecode() {
        XCTAssertFalse(WallpaperVisibilityPolicy.shouldSuspendDecode(
            intendedToPlay: true,
            windowReportsVisible: false,
            hasPresentedFrame: true,
            fullscreenAppCoversDisplay: false
        ))
        XCTAssertTrue(WallpaperVisibilityPolicy.shouldKeepDecoding(
            intendedToPlay: true,
            windowReportsVisible: false,
            hasPresentedFrame: true,
            fullscreenAppCoversDisplay: false
        ))
    }

    /// A visible desktop with a frame keeps decoding.
    func testVisibleDesktopKeepsDecoding() {
        XCTAssertFalse(WallpaperVisibilityPolicy.shouldSuspendDecode(
            intendedToPlay: true,
            windowReportsVisible: true,
            hasPresentedFrame: true,
            fullscreenAppCoversDisplay: false
        ))
        XCTAssertTrue(WallpaperVisibilityPolicy.shouldKeepDecoding(
            intendedToPlay: true,
            windowReportsVisible: true,
            hasPresentedFrame: true,
            fullscreenAppCoversDisplay: false
        ))
    }

    /// User/power pause: we are not intending to play, so occlusion is irrelevant.
    func testNotIntendedToPlayNeverSuspendsViaOcclusion() {
        XCTAssertFalse(WallpaperVisibilityPolicy.shouldSuspendDecode(
            intendedToPlay: false,
            windowReportsVisible: false,
            hasPresentedFrame: true,
            fullscreenAppCoversDisplay: true
        ))
        XCTAssertFalse(WallpaperVisibilityPolicy.shouldKeepDecoding(
            intendedToPlay: false,
            windowReportsVisible: true,
            hasPresentedFrame: true,
            fullscreenAppCoversDisplay: false
        ))
    }

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

    /// A single occlusion sample must not flip decode — that is the
    /// pause/resume twitch during ordinary desktop use.
    func testOcclusionChangeNeedsStableSamples() {
        XCTAssertFalse(WallpaperPlaybackPolicy.shouldCommitOcclusionChange(
            currentlySuspended: false,
            wantSuspended: true,
            consecutiveAgrees: 1
        ))
        XCTAssertTrue(WallpaperPlaybackPolicy.shouldCommitOcclusionChange(
            currentlySuspended: false,
            wantSuspended: true,
            consecutiveAgrees: WallpaperPlaybackPolicy.occlusionStableSamples
        ))
    }

    /// Once paused, a single "visible" sample must not resume either.
    func testOcclusionResumeNeedsStableSamples() {
        XCTAssertFalse(WallpaperPlaybackPolicy.shouldCommitOcclusionChange(
            currentlySuspended: true,
            wantSuspended: false,
            consecutiveAgrees: 1
        ))
        XCTAssertTrue(WallpaperPlaybackPolicy.shouldCommitOcclusionChange(
            currentlySuspended: true,
            wantSuspended: false,
            consecutiveAgrees: WallpaperPlaybackPolicy.occlusionStableSamples
        ))
    }

    func testNoOcclusionCommitWhenStateAlreadyMatches() {
        XCTAssertFalse(WallpaperPlaybackPolicy.shouldCommitOcclusionChange(
            currentlySuspended: true,
            wantSuspended: true,
            consecutiveAgrees: 99
        ))
    }

    func testReassertSkippedWhenWindowAlreadyPinned() {
        XCTAssertFalse(WallpaperPlaybackPolicy.shouldReassertWindow(
            levelMatches: true,
            overlayShouldShow: true,
            isOrderedIn: true,
            alphaIsFull: true
        ))
    }

    func testReassertWhenLevelDropped() {
        XCTAssertTrue(WallpaperPlaybackPolicy.shouldReassertWindow(
            levelMatches: false,
            overlayShouldShow: true,
            isOrderedIn: true,
            alphaIsFull: true
        ))
    }

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
}
