import Foundation

/// Pure stall-detection logic for the desktop playback watchdog (v1.4 Wave 1).
///
/// The category's #1 complaint is "the wallpaper freezes and I have to reopen
/// the app." In Release there is no stall detection at all, and the renderers
/// keep presenting the last decoded frame, so a wedged `AVPlayer` simply looks
/// frozen. `DesktopWindowController` samples each renderer's playback clock on
/// a timer and, when the clock stops advancing while playback is *intended*
/// (and not deliberately paused by `PowerManager`), nudges it back to life.
///
/// The decision is kept here — pure, no AVFoundation or AppKit — so it can be
/// unit-tested in isolation from the timer and the renderers.
enum PlaybackWatchdog {

    /// How often the controller samples playback progress.
    static let interval: TimeInterval = 5

    /// Consecutive frozen samples before we treat it as a real stall and
    /// recover. Two samples (~`interval` × 2 seconds) avoids acting on a
    /// single unlucky read while still self-healing well within the window a
    /// frustrated user would otherwise reach for the app.
    static let frozenSamplesBeforeRecovery = 2

    /// Whether a renderer looks frozen *this sample*: it is meant to be
    /// playing, the system isn't deliberately paused, and the playback clock
    /// has not advanced since the previous sample.
    ///
    /// A `nil` time — no player loaded (e.g. a still image) or an item that is
    /// not ready yet — is never considered frozen.
    static func isFrozen(
        previous: TimeInterval?,
        current: TimeInterval?,
        intendedToPlay: Bool,
        shouldBePaused: Bool
    ) -> Bool {
        guard intendedToPlay, !shouldBePaused else { return false }
        guard let previous, let current else { return false }
        return current == previous
    }
}
