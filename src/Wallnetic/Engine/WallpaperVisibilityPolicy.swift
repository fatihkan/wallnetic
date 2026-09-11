import Foundation

/// Pure rules for when the desktop overlay may cover the real wallpaper
/// and when decode may be paused. Kept free of AppKit so the combinations
/// that produce a black desktop are unit-testable.
///
/// The overlay window is an opaque surface sitting *above* the system
/// wallpaper. If it is shown without a decoded frame, or if decode is
/// paused before the first frame, the user sees a black rectangle — the
/// failure this policy exists to prevent, including during wallpaper
/// switches, window open/close, and occlusion bursts.
enum WallpaperVisibilityPolicy {

    /// Decode may be suspended only for a *fullscreen* cover, with a frame
    /// already on screen. A windowed foreground app must never pause the
    /// wallpaper: `NSWindow.occlusionState` flaps for desktop-level windows
    /// and those pause/resume cycles are the brief freeze, uneven rate and
    /// keyframe rollback the user sees around a normal (non-fullscreen) app.
    static func shouldSuspendDecode(
        intendedToPlay: Bool,
        windowReportsVisible: Bool,
        hasPresentedFrame: Bool,
        fullscreenAppCoversDisplay: Bool
    ) -> Bool {
        guard fullscreenAppCoversDisplay else { return false }
        return intendedToPlay && !windowReportsVisible && hasPresentedFrame
    }

    /// Keep decoding whenever playback is intended, except a stable
    /// fullscreen cover that already has a frame on screen.
    static func shouldKeepDecoding(
        intendedToPlay: Bool,
        windowReportsVisible: Bool,
        hasPresentedFrame: Bool,
        fullscreenAppCoversDisplay: Bool
    ) -> Bool {
        guard intendedToPlay else { return false }
        if !fullscreenAppCoversDisplay { return true }
        if windowReportsVisible { return true }
        return !hasPresentedFrame
    }

    /// The overlay must not cover the desktop until it has something to show.
    /// Once a frame exists it stays up across reloads so a swap cannot
    /// flash black (the previous frame remains until the next one is ready).
    static func shouldShowOverlay(hasPresentedFrame: Bool) -> Bool {
        hasPresentedFrame
    }
}

/// Rules that keep wallpaper motion smooth. Re-ordering a desktop window,
/// restarting a player that is already at rate 1, or flipping occlusion on
/// every burst notification all present as a visible twitch.
enum WallpaperPlaybackPolicy {

    /// Consecutive occlusion reads that must agree before we pause or resume
    /// decode. Desktop-level windows get contradictory `.visible` flags;
    /// acting on a single sample stutters the picture.
    static let occlusionStableSamples = 3

    /// Commit an occlusion pause/resume only after the desired state has
    /// held for `occlusionStableSamples` reads in a row.
    static func shouldCommitOcclusionChange(
        currentlySuspended: Bool,
        wantSuspended: Bool,
        consecutiveAgrees: Int
    ) -> Bool {
        currentlySuspended != wantSuspended
            && consecutiveAgrees >= occlusionStableSamples
    }

    /// Touching a window that is already at the right level and on-screen
    /// (`orderFront`, collectionBehavior rewrite) makes the compositor hitch.
    static func shouldReassertWindow(
        levelMatches: Bool,
        overlayShouldShow: Bool,
        isOrderedIn: Bool,
        alphaIsFull: Bool
    ) -> Bool {
        guard overlayShouldShow else { return false }
        return !levelMatches || !isOrderedIn || !alphaIsFull
    }

    /// `AVPlayer.play()` on a player that is already running can restart
    /// the buffer and hitch. Only issue play from a full stop.
    static func shouldIssuePlay(currentRate: Float) -> Bool {
        currentRate == 0
    }

    /// `automaticallyWaitsToMinimizeStalling` drifts rate below 1 when a
    /// foreground app steals the decoder, which looks like uneven speed.
    /// Pin back to 1.0 without seeking (a seek rolls back to the last
    /// keyframe — "jumped back a few frames").
    static func shouldCorrectRate(currentRate: Float, intendedToPlay: Bool) -> Bool {
        guard intendedToPlay else { return false }
        return currentRate > 0 && abs(currentRate - 1) > 0.02
    }

    /// Resigning active (windowed app in front, or our own window closing)
    /// must not stop presenting. macOS pauses `MTKView` / throttles inactive
    /// windows; a cold restart when the wallpaper is uncovered is the hitch
    /// on "foreground windowed → no longer in front".
    static func shouldKeepPresentingWhileInactive(intendedToPlay: Bool) -> Bool {
        intendedToPlay
    }
}
