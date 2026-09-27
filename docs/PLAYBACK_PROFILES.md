# Playback profiles

Settings > Playback offers Quality, Balanced (the default), and Battery Saver.
The preference is saved under `performance.mode`, including compatibility with
the previous display-name values and lowercase `balanced` default.

| Profile | Metal presentation target | AVPlayer fallback |
| --- | --- | --- |
| Quality | Up to 60 draws/second | Original video cadence |
| Balanced | Up to 30 draws/second | Original video cadence |
| Battery Saver | Up to 15 draws/second | Original video cadence |

Metal limits work in the locked display-link scheduler before dispatching it to
the main queue. Changing only MTKView.preferredFramesPerSecond would not limit
the app's manually driven draw loop. Pending requests still coalesce, and an
invalidated playback session cannot be restarted by a profile change.

These are presentation targets, not decoder, CPU, memory, or energy limits.
The display link still receives display callbacks, and AVFoundation may decode
at the source frame rate. No frames are interpolated, no files are rewritten,
and video resolution stays unchanged. Source and display refresh rates can
limit visible motion below the selected target.

AVPlayerLayer retains native timing for local files. The settings UI explicitly
explains this limitation. A trial of changing video compositions at runtime
moved a paused player's clock backwards on macOS 26.6.2, so that approach is
excluded from this change. Lowering playback rate or applying network bitrate
preferences would not provide an appropriate local-video frame-rate limit.

Each desktop renderer subscribes to the saved profile. Existing displays update
immediately, newly connected displays receive the current preference, and
disconnected displays release their subscriptions. Updates do not call play,
pause, seek, load, or recreate desktop windows. Manual and automatic pause
ownership remain with the existing playback and power controllers.

## Validation

The full suite passed 191 tests (0 failures) on Apple M4 / macOS 26.6.2,
including 13 PlaybackRendererTests. The Release build succeeded for both
arm64 and x86_64, and both architectures were verified in the app and widget.
Coverage includes normal playback speed and pause preservation in both
engines, changes during asynchronous loading, saved preferences, existing/new
display subscriptions, callback coalescing, session invalidation, and simulated
59.94/60/120/144 Hz displays at each target cadence.

### Local measurement — 2026-09-27

An optimized standalone harness compiled the renderer sources from baseline
`f9e5083` and this change. It played the same synthetic 1920×1080, 60 FPS H.264
file in a 960×540-point window at 2× scale. Each sample used a two-second warmup
and five-second measurement. Two displays were connected; this CPU comparison
used one renderer. Other applications, including the installed Wallnetic app,
remained running.

| Metal case | Draws/second | Process CPU (% of one core) | Playback rate |
| --- | ---: | ---: | ---: |
| Before | 59.87 | 7.71 | 1.0 |
| Quality | 59.68 | 8.49 | 1.0 |
| Balanced | 29.75 | 6.29 | 1.0 |
| Battery Saver | 14.97 | 4.99 | 1.0 |

Draws were counted at the MTKView delegate and CPU time measured with
`getrusage`. These are short, single-run observations, not guaranteed savings.
They exclude WindowServer and other processes, GPU time and power draw. Decoder
frame counts and battery life were not measured. In particular, Quality's small
CPU increase over the baseline needs longer sampling before interpretation.

The AVPlayer fallback used about 2.68% of one CPU core before the change and
2.85%, 2.93%, and 2.66% in Quality, Balanced, and Battery Saver respectively;
playback rate stayed at 1.0. Its presentation FPS was not measured by this
Metal-delegate counter. These samples support no claim of AVPlayer savings.

A second smoke run displayed one Metal renderer on each of the two connected
monitors (VA1655-FHD and ASUS VG24VQE) in 480×270-point windows. Both subscribed
to the same PerformanceManager. After each live profile change, three-second
samples measured approximately 59.0, 29.9, and 15.2 draws/second on **each**
display. Both players stayed at rate 1.0 and retained their presented-frame
state. Short sampling windows include frame-boundary rounding. This verifies
two active displays, but not display unplug/reconnect or full-screen GPU load.

Physical Intel playback and sleep/wake, lock/unlock and hot-plug checks remain
part of release validation for issue #248. A universal build does not replace
physical Intel testing. This issue should remain open for that validation.
