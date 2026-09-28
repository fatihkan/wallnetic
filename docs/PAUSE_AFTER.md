# Pause After

Settings > Playback > Pause After lets wallpaper motion stop after an interval
while keeping the last valid frame on the desktop. It is disabled by default.
Presets are 15 seconds, 30 seconds, 1 minute, 5 minutes, and 15 minutes. Custom
intervals accept 1–86,400 seconds.

Choose a library item in Wallpaper override to change only that file:

- **Use Default** follows the global interval, including future changes.
- **Never Pause** overrides the global interval and allows continuous motion.
- A preset or custom interval overrides the global duration.

Preferences persist locally, with overrides keyed by the standardized file path
like other library metadata. Changing a display title does not lose its override.

## Playback rules

| Event | Behavior |
| --- | --- |
| First valid frame available | Begin the interval while playback is allowed. An empty loading overlay is never frozen. |
| Duration expires | Pause that display's renderer and retain its frame. Stop its watchdog recovery; stop the duration timer, watchdog, and playback activity when all displays are held. |
| Explicit Play | Start fresh intervals on all displays, subject to power restrictions. |
| Explicit Pause | Hold all displays until explicit Play; wallpaper rotation, preference edits, unlock, and desktop-clear replay cannot override it. |
| Wallpaper changes | Reset only the affected display(s). Reapplying the same file does not silently extend a running interval. |
| Power, lock, sleep, screen saver, fullscreen restriction | Suspend playback. Existing power-manager ownership and automatic-resume preferences still decide whether resuming is allowed. |
| Allowed automatic resume | Start fresh intervals; a duration pause retains intent, so unlock can replay it. A manual pause does not retain that permission. |
| Effective duration changes | Start a fresh interval on affected displays when allowed. Never Pause removes the limit. Unaffected overrides keep their deadlines. |
| Display removed/added | Remove its old session; a newly assigned renderer gets a fresh interval and its wallpaper's effective setting. |

The timer uses monotonic uptime and checks every 250 ms while needed; busy run
loops can delay expiration. It never seeks, changes video speed, discards the
retained frame, or writes modified videos. The menu bar explains a duration pause
when every active wallpaper has timed out; the widget reflects paused playback.

## Optional desktop-clear replay

Replay when the desktop becomes clear is off by default. When enabled, a utility
queue samples on-screen regular app-window geometry every two seconds. Two
consecutive covered samples followed by two consecutive clear samples constitute
one transition. Only an expired display is replayed. An initially clear desktop
does not replay continuously, and another display's timer is not reset.

This detects regular layer-zero windows intersecting each display, rather than
all possible floating panels or system overlays. It does not read window titles,
capture screens, request Accessibility/Screen Recording access, or use private
APIs. Failed/incomplete metadata is not treated as permission to replay. Sampling
stops when disabled, manually/power paused, or no displayed wallpaper has a limit.

## Validation

The full local suite passed 195 tests on Apple M4 / macOS 26.6.2. This includes
duration-boundary and lifecycle tests, independent display deadlines, persistence,
manual pause precedence, overlapping power restrictions, and desktop-clear edge
stability. Real AVPlayer and Metal renderer tests verified a retained frame, a
stopped playback clock after expiry, and explicit resume without changing speed.

A separate smoke run on two connected monitors used different videos with 1 s
and 2 s intervals. At 1.2 s only the first player had paused; at 2.2 s both had
paused with valid frames. MTKView draw counts stopped advancing while held.
Replaying one display left the other paused, automatic play did not override
manual Pause, and explicit Play resumed both.

The universal Release build passed for arm64 and x86_64. Physical Intel playback,
macOS 13, actual sleep/wake, lock/unlock, display hot-plug, and desktop-clear UX
remain manual release checks. Synthetic lifecycle events are not substitutes for
those hardware checks; issue #249 remains open for release validation.
