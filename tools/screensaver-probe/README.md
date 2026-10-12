# Isolated screen saver research probe

Development artifact for [#259](https://github.com/fatihkan/wallnetic/issues/259).
It is **not an installed screen saver, an app extension, a lock-screen feature,
or a distributable release**. See [the decision record](../../docs/SCREENSAVER_FEASIBILITY.md).

Requirements: a Mac with Xcode command-line tools and a graphical login session
for the optional playback checks. Deployment target: macOS 13.0. The build emits
both arm64 and x86_64 slices; native runtime checks exercise the current machine's
architecture only.

From the repository root:

```sh
tools/screensaver-probe/build.sh        # compile/sign locally; CI uses this
tools/screensaver-probe/build.sh --run  # also show two ordinary test windows
```

Each run creates a new `.build/screensaver-probe.XXXXXX/` directory containing:

- `WallneticScreenSaverProbe.saver`: a ScreenSaverView plug-in that loops the
  repository's original `AuroraSample.mp4` through AVQueuePlayer/AVPlayerLooper
  and AVPlayerLayer, muted and without preventing display sleep.
- `ScreenSaverProbeHost`: a separate development host that loads that bundle,
  runs bounded checks, closes its windows and exits nonzero on failure.

The signature is ad-hoc, for local development only. The script does not use
production signing credentials or submit anything for notarization. It does not
install a bundle, register/select a system screen saver, change the user's
wallpaper, modify lock settings, remove quarantine, or terminate system services.
The host accepts a bundle path only for the locally built probe; do not use it to
load untrusted plug-ins. No network or external media is used by the probe.

The 16 runtime checks cover two instances, preview input, real decoder progress,
a completed six-second loop, portrait resize, duplicate start/stop, resource
release, synthetic in-process screen sleep/wake notifications, stop during sleep,
view detachment, 20 restart/stop cycles, and observer lifetime. Both view sizes
run as ordinary windows on the current display. This is **not** physical
multi-monitor, actual sleep/wake, login-window, system-host or signed-sandbox
validation. The harness fails normally instead of deliberately crashing.

Nothing is installed outside the printed build directory. Removing that exact
output directory removes the research artifacts; no system restore step is
needed. Leave the user's real screen saver and lock settings alone when working
on the probe. Follow the production validation gates in the decision record
before considering a real installation or release.

The bundled sample and code use the repository MIT license. The build copies
that license into the probe. Sample provenance: [ONBOARDING_SAMPLE.md](../../docs/ONBOARDING_SAMPLE.md).
