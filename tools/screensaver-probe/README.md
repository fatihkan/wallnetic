# Standalone screen saver development host

This harness began as the isolated [#259](https://github.com/fatihkan/wallnetic/issues/259)
research probe. It now builds and tests the actual [#274](https://github.com/fatihkan/wallnetic/issues/274)
candidate in `src/WallneticScreenSaver`; there is no duplicate plug-in implementation.
The original research code and 16-check result remain in the #275 Git history.

```sh
tools/screensaver-probe/build.sh             # compile candidate + host
tools/screensaver-probe/build.sh --run       # runtime and packaging checks
tools/screensaver-probe/build.sh --benchmark # also report host CPU/footprint
```

Requires macOS, Xcode command-line tools and a graphical login session for runtime
checks. Output goes to a new `.build/screensaver-candidate.XXXXXX` directory. The
candidate and host are universal, ad-hoc signed developer artifacts. No system
screen saver, wallpaper, lock policy, sleep state or security setting is changed.
Nothing is installed, registered or selected. Remove only that output directory
to clean up. Do not pass untrusted plug-ins to the host.

The host runs two ordinary windows, emulates the public one-second animation
callback and observes real AVFoundation playback. It checks loops, per-view
lifecycle, resize, resource release, synthetic system/display sleep, reattachment,
deallocation, repeat start/stop and stall timeout/recovery. The external host
pauses its own queue to simulate a stalled decoder; the plug-in has no test-only
behavior. Separate processes load private copies with
missing, empty, corrupt, oversized or symlinked media and check safe fallback.
The Python runner imposes a timeout per subprocess and verifies packaging rejects
bad payloads and ad-hoc distribution. No test media outside its build directory
is modified. Logs containing an expected `Validation failed` are negative checks;
an unexpected exit or failed assertion makes the suite fail.

`--benchmark` reports the host's process CPU and physical footprint only. It does
not measure GPU/decoder-service memory or energy, and is not a system-host result.
Actual multi-display, sleep/lock, signed sandbox, supported-OS and installation
validation remain separate release gates.

See [candidate behavior, evidence and release gates](../../docs/STANDALONE_SCREEN_SAVER.md)
and [the original feasibility record](../../docs/SCREENSAVER_FEASIBILITY.md).
