import Foundation

/// Pure resume-decision logic for ``PowerManager`` (v1.4.2).
///
/// v1.4.1 added pausing on screen lock, fast user switching and the screen
/// saver, and let those resume paths bypass the "resume automatically" setting
/// — locking is not a pause the user asked for, so leaving the wallpaper dead
/// after every unlock would be wrong.
///
/// What that shipped without was any notion of *who* paused. Every resume path
/// called straight through, so a wallpaper the **user** had paused came back to
/// life on the next unlock, wake or screen-saver exit. For anyone who had
/// turned "resume automatically" off, the setting stopped working entirely.
///
/// The rule is therefore ownership-based: only a pause this app caused may be
/// undone by this app. It is kept here — pure, no AppKit — so the exact
/// combination that shipped broken is unit-testable, following the same
/// precedent as ``PlaybackWatchdog``.
enum PowerPauseOwnership {

    /// Whether a pause should be *claimed* as ours when a power condition
    /// fires.
    ///
    /// Only claim it if the wallpaper was actually playing. If the user had
    /// already paused, claiming here would hand us permission to "resume" a
    /// pause we never caused — which is the v1.4.1 defect, just moved.
    static func shouldClaimPause(wallpaperIsPlaying: Bool) -> Bool {
        wallpaperIsPlaying
    }

    /// Whether playback should resume now.
    ///
    /// - Parameters:
    ///   - pausedByPower: we paused it and have not handed control back.
    ///   - shouldBePaused: some power condition is still active.
    ///   - respectAutoResume: `false` for pauses the user never asked for
    ///     (lock, user switch, screen saver, wake), where the auto-resume
    ///     setting must not strand the wallpaper.
    ///   - autoResumeEnabled: the user's "resume automatically" preference.
    static func shouldResume(
        pausedByPower: Bool,
        shouldBePaused: Bool,
        respectAutoResume: Bool,
        autoResumeEnabled: Bool
    ) -> Bool {
        // A condition is still active — nothing to resume into.
        guard !shouldBePaused else { return false }
        // Never override the user's own Pause.
        guard pausedByPower else { return false }
        return !respectAutoResume || autoResumeEnabled
    }
}
