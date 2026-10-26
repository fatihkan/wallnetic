# Repeatable playback measurements

Issue [#255](https://github.com/fatihkan/wallnetic/issues/255) separates tooling from
the baseline and physical-device matrix. **This change prepares the tools. The
full measurement campaign, energy baseline, and regression thresholds are pending.**
Short development smoke runs are not performance evidence. The older five-second
observations in [PLAYBACK_PROFILES.md](PLAYBACK_PROFILES.md) remain historical only.

## Scope and preparation

`tools/playback-benchmark/benchmark.py` compiles the current tracked Metal and
AVPlayer renderers with `-O`, Swift 5 mode and deployment target macOS 13. It
extracts their shared protocol/conformances from `DesktopWindowController.swift`
without copying renderer logic or starting the app controller. Build fingerprints
include the source files, tool sources, compiler, SDK, architecture and binaries;
the collector refuses stale binaries. The shipping app version stays unchanged.

The host opens ordinary, temporary playback windows: one per explicitly selected
connected display. It does not exercise the app UI, desktop overlay, pause-policy
controller, sandbox, screensaver or login-item lifecycle. It does not install an
app, change wallpaper/preferences, request capture permissions, take screenshots,
lock the session or suppress system/display sleep. It needs a logged-in graphical
session for playback. Compiling and reporting tests do not start playback.

Use Xcode command-line tools and Python 3 (standard library only):

```sh
python3 tools/playback-benchmark/benchmark.py build
python3 -m unittest discover -s tools/playback-benchmark -p 'test_*.py'
python3 tools/playback-benchmark/benchmark.py fixtures .build/benchmark-media-v1
```

The last command creates a **new** directory containing two silent, ten-second
looping clips. Both use the same original moving radial gradients; no third-party
footage, fonts or music. The generated files are redistributable under the
repository MIT license, copied into the output alongside `fixtures.json`.

| Recipe | Resolution | Cadence | Codec | Target bitrate |
| --- | --- | --- | --- | --- |
| h264 | 1920 × 1080 | 30 FPS | H.264 (`avc1`) | 6 Mbit/s |
| hevc | 3840 × 2160 | 60 FPS | HEVC (`hvc1`) | 16 Mbit/s |

These are SDR, Rec.709-tagged synthetic low-complexity workloads, not representative
of every wallpaper or HDR video. Target bitrate is not a measured bitrate guarantee.
Record separate licensed high-complexity/HDR fixtures before drawing broader conclusions.
Generation checks codec, dimensions, cadence and duration; unavailable HEVC encoding
fails without substituting H.264 or reducing resolution. Failed generation leaves
an incomplete directory without a complete manifest; use a new path for retry.

Encoder output can vary by OS/hardware. Archive and reuse **the same encoded
files and SHA-256 manifest** on all comparison machines. Matching recipes alone
does not establish byte-identical media. Keep the generator fingerprint and license.

## Collecting a renderer configuration

Collect later in the agreed measurement session. Default: 30-second warmup after
first-frame readiness, 60-second measurement, five fresh-process repetitions.
Allow the machine to cool between configurations; alternate baseline/candidate
order across sessions. Leave brightness, refresh rate, resolution, ambient
conditions and background workloads fixed. Record the installed Wallnetic's
running state and other workloads in `--context`; the tool never terminates them.

```sh
python3 tools/playback-benchmark/benchmark.py run \
  --media .build/benchmark-media-v1 --fixture h264 \
  --engine metal --profile balanced --screens 0 \
  --context 'Rig A; AC; brightness fixed; background workloads documented' \
  --output .build/benchmarks/rig-a-metal-balanced-h264-session-1
```

Repeat for both fixtures, `metal`/`avplayer`, `quality`/`balanced`/`battery`, and
each intended display/power configuration. `--screens 0,1` selects two **physical
connected screens**, not two windows on one screen. Default content size is
960 × 540 points. `--width`/`--height` select another size; it must fit every
selected screen. Native-resolution and scaled workloads are separate cases.
AVPlayer keeps source cadence across profiles; Metal draw targets are not decoder limits.

Each repetition stores raw JSON and stderr in a new directory, followed by a
summary. Prior results are never overwritten. A failure stops collection and
preserves completed records without inventing a successful final summary. The
subprocess has a bounded readiness/collection timeout. For a tooling-only smoke
check, use `--warmup 1 --seconds 2 --repeats 1`; it is ineligible for a baseline.

```sh
python3 tools/playback-benchmark/benchmark.py summarize \
  .build/benchmarks/rig-a-metal-balanced-h264-session-1/[0-9][0-9].json
```

Only identical build, fixture hash, hardware, OS, display topology, power state,
window size, sampling configuration and context may be averaged. Duplicated run
IDs and interrupted samples are rejected. Power/thermal changes, non-nominal
thermal state, reported occlusion, stalled sampling and playback rate errors make
a run ineligible. AppKit visibility does not prove that every pixel was unobscured;
the operator must check visibility. Window positions/topology must remain stable.

The summarizer validates comparison, eligibility and aggregated measurement fields
before combining runs. Eligibility flags must be JSON booleans, not strings or
numbers. Measurements must be finite nonnegative numbers; booleans are rejected.
Unavailable optional metrics must be explicit `null` values. Every supplied
measurement is checked even when another repetition reports that metric unavailable;
the summary then keeps that metric `null` instead of averaging a partial set.
Missing required fields, malformed field types, duplicate JSON keys and non-finite
JSON numbers fail with a command-line error. Fixture durations must also be finite.
These checks preserve schema-v1 reports and do not authenticate the measurements
or replace review of raw samples, traces and the physical-device matrix.

## Metrics and limits

| Field | Meaning / collection |
| --- | --- |
| CPU percent | Delta of process user + system CPU seconds from `getrusage`, divided by measured monotonic wall time × 100. **100% is one logical core**, so >100% is valid. Includes host sampling overhead, excludes other processes. |
| Physical footprint / resident bytes | Public `proc_pid_rusage` for this PID; once-per-second samples. Reported footprint peak is a **sampled** peak, not the true lifetime peak. Raw samples preserve RSS. |
| Package idle / interrupt wakeups | Per-process cumulative counter deltas / measured seconds. Separate fields; they are not watts or total system wakeups. Unavailable data is `null`. |
| Metal delegate intervals | Count and p95/max spacing of `MTKViewDelegate.draw` callbacks. A call may reuse a frame or return without presenting. **Not decoded FPS, unique frames or displayed frame pacing.** AVPlayer is `null`. |
| Playback | Player clock/rate snapshots and initial renderer readiness. No claim of continuous visible output or black-frame freedom. |
| GPU, energy, auxiliary processes | `null` in the automatic report. Collect separately with Instruments/Activity Monitor and annotate scope and instrument version. No fabricated zero values. |

The host holds `userInitiatedAllowingIdleSystemSleep` during collection. Record
this activity policy when comparing results. It deliberately allows sleep; discard
interrupted runs. The original app's different window, policy and activity behavior
requires its own measurements. Hashing/media inspection occurs before warmup.

For GPU/energy traces, use the macOS tools available on the measurement machine
and record their names/versions, capture interval, process attribution and units.
Check platform availability in Apple's [power measurement documentation](https://developer.apple.com/documentation/xcode/measuring-your-app-s-power-use-with-power-profiler).
If a metric is unsupported, record `unavailable` and the reason. Activity Monitor's
Energy Impact is a relative observation, not watts or a battery-life estimate.
WindowServer/decoder helper costs can be shared with other apps: include an idle
control under matching workloads, preserve raw traces, and do not attribute their
entire CPU/GPU load to Wallnetic. Screen recording can alter GPU/CPU cost; perform
visual recordings in a separate pass and identify their overhead.

## Full-app and device matrix — all pending

The following checks use a separately identified app build and are **not covered
by the isolated host**. Record actual machine identity label (no serial numbers),
OS/build, app commit/version/configuration/signing, media SHA-256, power, thermal
state, brightness, refresh/HDR settings, display geometry, profile, renderer and
background apps for every case. Keep planned/untested/unsupported/failed distinct.

| Scenario | Procedure / observable evidence | Status |
| --- | --- | --- |
| Apple Silicon / physical Intel, supported OS versions | Run both codecs/engines/profiles on each actual machine; emulation or universal compilation is not hardware validation. | Untested |
| One / multiple displays | Per-display native/scaled playback, mirrored/extended setup recorded, mixed refresh rates, disconnect/reconnect and display changes. | Untested |
| App UI open / closed | Compare visible desktop with library/settings open then closed; stable playback and resource traces. | Untested |
| Covered / fullscreen desktop | Windowed coverage then fullscreen coverage/uncover. Windowed coverage must not pause playback; a frontmost fullscreen app pauses every display while "Pause when fullscreen app is active" is on. Capture those transitions and the first restored frame. | Untested |
| Lock / unlock and sleep / wake | Operator-controlled transitions; record pause/resume, system wallpaper fallback, time to first visible frame and absence of black flashes. Do not include asleep time in an active playback sample. | Untested |
| AC / battery / Low Power Mode / thermal | Matching AC and battery sessions on applicable hardware; record Low Power Mode and policy changes separately. Desktops without a battery are not applicable. | Untested |
| Switching / loop boundaries / frame pacing | At least 20 A↔B switches and 20 loop boundaries per configuration; timestamp requests and first visible frame, inspect drops/repeats/black frames separately from resource capture. Include failed/missing media fallback. | Untested |
| Long running / resource cleanup | At least 30 minutes playback plus repeated start/stop; record memory trend, released resources and retry/stall behavior. | Untested |
| GPU / energy / shared-process overhead | Separate instrumented and idle-control passes, matching durations and recorded tool overhead. | Untested |

## Baselines and regression review

Store approved raw JSON, summaries, encoded fixture manifests, visual observations
and trace locations in a dated artifact set. Results currently remain under ignored
`.build/`; copy approved artifacts to the release/issue record after review. Do not
publish user paths, private process details or machine serial numbers. No baseline
artifact or performance pass is added by this implementation.

At least five valid repetitions satisfy only the minimum collection rule. Summaries
retain median, median absolute deviation and range; no outlier is silently removed.
Repeat baseline sessions on different occasions to estimate within-machine noise.
Before selecting thresholds, document that measured noise, expected effect size,
metric units, absolute and relative tolerances, and false-positive behavior on
another unchanged-build session. Then compare candidate summaries **separately**
under identical conditions; never average baseline and candidate builds together.
Thresholds remain `null` until supported by those measurements. A faster result
does not override failed visual, lifecycle, security or cleanup checks.

### Comparing recorded sessions

The read-only comparison command accepts the raw records for each session:

```sh
python3 tools/playback-benchmark/benchmark.py compare \
  --baseline .build/benchmarks/baseline/[0-9][0-9].json \
  --candidate .build/benchmarks/candidate/[0-9][0-9].json
```

It prints JSON without rebuilding, opening playback windows, collecting new
measurements or modifying input files. Each side first passes the normal strict
validation and summarization rules. A side containing mixed builds is rejected,
as are run IDs duplicated within or across sessions. Separate sessions of an
unchanged build are allowed for studying noise.

Hardware, OS, renderer, profile, fixture metadata including the encoded-file hash,
display topology, window size, power state at the start, activity policy, warmup,
sample duration/interval and operator context must match. The compiler, SDK,
architecture, optimization and deployment target must also match, along with the
recorded source hashes for `Runner.swift`, `Metrics.c`, `Metrics.h` and
`benchmark.py`. Build/revision and renderer/app source changes are allowed. A
collector or toolchain change requires new matching sessions; do not edit old
metadata to force a comparison. JSON checks do not authenticate measurements or
prove that unrecorded physical conditions were identical.

The report retains both summaries, run IDs and build metadata. For every CPU,
memory and wakeup metric it includes each median, median absolute deviation and
range, plus `candidate − baseline` and `(candidate − baseline) / baseline × 100`.
CPU absolute changes are **percentage points of one logical core**; relative
changes are percentages. Bytes and wakeups/second keep their own units. A negative
delta describes a lower recorded value, not a verified improvement.

If either side lacks a metric, that side and both deltas remain `null`; the other
side's summary is retained. A zero baseline has no defined relative percentage,
even when the candidate is also zero. An unrepresentable relative percentage is
also `null`, with a distinct `relative_change_status`. Neither case fabricates a
zero, infinity or a pass/fail conclusion.

`eligible_for_comparison` requires both sessions to meet the existing minimum
collection rules and have no uncommitted compiled inputs. Short, interrupted,
flagged or dirty-input sessions can still be inspected but are explicitly
ineligible, with reasons. This eligibility does not certify a baseline or exclude
noise. `performance_conclusion` stays `not_assessed`, regression thresholds stay
`null`, and full-app/device validation stays `not_performed` until the separately
planned measurements and acceptance checks are complete.
