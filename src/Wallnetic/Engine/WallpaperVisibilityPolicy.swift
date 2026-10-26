import Foundation

/// Pure rules for when the desktop overlay may cover the real wallpaper.
/// Kept free of AppKit so the combinations that produce a black desktop are
/// unit-testable.
///
/// The overlay window is an opaque surface sitting *above* the system
/// wallpaper. If it is shown without a decoded frame, the user sees a black
/// rectangle — the failure this policy exists to prevent, including during
/// wallpaper switches and window open/close.
enum WallpaperVisibilityPolicy {

    /// The overlay must not cover the desktop until it has something to show.
    /// Once a frame exists it stays up across reloads so a swap cannot
    /// flash black (the previous frame remains until the next one is ready).
    static func shouldShowOverlay(hasPresentedFrame: Bool) -> Bool {
        hasPresentedFrame
    }
}

/// Rules that keep wallpaper motion smooth. Re-ordering a desktop window or
/// restarting a player that is already at rate 1 presents as a visible twitch.
enum WallpaperPlaybackPolicy {

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
