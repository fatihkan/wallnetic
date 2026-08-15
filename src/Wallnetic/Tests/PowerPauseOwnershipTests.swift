import XCTest
@testable import Wallnetic

final class PowerPauseOwnershipTests: XCTestCase {

    // MARK: - The v1.4.1 regression these tests exist for

    /// Pause the wallpaper yourself, lock the Mac, unlock: it must stay paused.
    /// v1.4.1 resumed it, because the unlock path bypassed the auto-resume
    /// setting without checking who had paused in the first place.
    func testUserPauseSurvivesUnlock() {
        // The user paused, so no power condition ever claimed ownership.
        XCTAssertFalse(PowerPauseOwnership.shouldResume(
            pausedByPower: false,
            shouldBePaused: false,
            respectAutoResume: false,   // unlock bypasses the setting
            autoResumeEnabled: true
        ))
    }

    /// Same, for someone who explicitly turned auto-resume off — v1.4.1 broke
    /// that setting outright on every lock, wake and screen-saver exit.
    func testUserPauseSurvivesUnlockWithAutoResumeDisabled() {
        XCTAssertFalse(PowerPauseOwnership.shouldResume(
            pausedByPower: false,
            shouldBePaused: false,
            respectAutoResume: false,
            autoResumeEnabled: false
        ))
    }

    /// A power condition claims the pause only when something was playing.
    func testClaimsPauseOnlyWhenPlaying() {
        XCTAssertTrue(PowerPauseOwnership.shouldClaimPause(wallpaperIsPlaying: true))
        XCTAssertFalse(PowerPauseOwnership.shouldClaimPause(wallpaperIsPlaying: false))
    }

    // MARK: - The behaviour v1.4.1 was built for, which must still hold

    /// A lock-induced pause resumes on unlock even with auto-resume off —
    /// otherwise the wallpaper is dead after every unlock, which is the whole
    /// reason the bypass exists.
    func testPowerPauseResumesOnUnlockDespiteAutoResumeDisabled() {
        XCTAssertTrue(PowerPauseOwnership.shouldResume(
            pausedByPower: true,
            shouldBePaused: false,
            respectAutoResume: false,
            autoResumeEnabled: false
        ))
    }

    func testPowerPauseResumesWhenAutoResumeEnabled() {
        XCTAssertTrue(PowerPauseOwnership.shouldResume(
            pausedByPower: true,
            shouldBePaused: false,
            respectAutoResume: true,
            autoResumeEnabled: true
        ))
    }

    /// Battery and fullscreen pauses *do* respect the setting.
    func testPowerPauseHonoursAutoResumeSettingOnOrdinaryPaths() {
        XCTAssertFalse(PowerPauseOwnership.shouldResume(
            pausedByPower: true,
            shouldBePaused: false,
            respectAutoResume: true,
            autoResumeEnabled: false
        ))
    }

    // MARK: - Never resume into a live condition

    func testNeverResumesWhileAConditionIsStillActive() {
        for respect in [true, false] {
            for auto in [true, false] {
                XCTAssertFalse(
                    PowerPauseOwnership.shouldResume(
                        pausedByPower: true,
                        shouldBePaused: true,
                        respectAutoResume: respect,
                        autoResumeEnabled: auto
                    ),
                    "respectAutoResume=\(respect) autoResumeEnabled=\(auto)"
                )
            }
        }
    }

    /// Ownership is not sticky: once we resume, PowerManager clears the latch,
    /// so a second resume attempt must not fire again on its own.
    func testResumeIsNotRepeatableWithoutANewPause() {
        XCTAssertTrue(PowerPauseOwnership.shouldResume(
            pausedByPower: true, shouldBePaused: false,
            respectAutoResume: false, autoResumeEnabled: true
        ))
        // PowerManager sets pausedByPower = false at this point.
        XCTAssertFalse(PowerPauseOwnership.shouldResume(
            pausedByPower: false, shouldBePaused: false,
            respectAutoResume: false, autoResumeEnabled: true
        ))
    }
}
