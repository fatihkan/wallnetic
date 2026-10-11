# Calm Mode and thermal-aware playback

## Controls

Use **Turn On Calm Mode** in the menu bar or the app's **Playback** menu to hold
wallpaper motion. **Command–Shift–M** toggles it while Wallnetic is active. The
same control is in Settings → Playback. On macOS 14 and later, Shortcuts offers
**Toggle Calm Mode** and the idempotent **Set Calm Mode** action with an Enabled
parameter. This feature adds no global keyboard monitor or permission request.

Calm Mode lasts for the current app session and resets when Wallnetic quits.
Turning it off restores the previous playback intent only when other pause
conditions allow it. A manually paused wallpaper stays paused. Each display's
existing presented frame remains available; if no frame has loaded yet, the
desktop overlay stays hidden instead of showing a black frame.

## Optional thermal policy

**Pause wallpaper when the Mac gets hot** is off by default. This preference
persists across launches. The policy uses `ProcessInfo.thermalState` and
`thermalStateDidChangeNotification`, with one-shot timers only while a state
transition is pending:

| System state | Playback response |
| --- | --- |
| Nominal or fair | No new hold. An existing heat hold clears after 60 continuous seconds in these states. |
| Serious | Pause after 10 continuous seconds of serious pressure. A brief return to nominal/fair cancels that pending pause. |
| Critical | Pause immediately. |

Renewed serious or critical pressure cancels a pending cooling recovery. Moving
between nominal and fair does not restart the cooling interval. Disabling the
option immediately removes only the heat hold. Thermal recovery restores prior
intent automatically; the existing auto-resume preference still governs battery,
Low Power Mode and fullscreen pauses. Clearing a heat hold never overrides a
power pause that the user has chosen not to auto-resume.

The policy pauses video motion in both renderers. It does not switch codecs,
reduce resolution, modify the saved performance profile or start a download.
Energy savings depend on media and hardware; no numerical saving is claimed.

The system state is read before notification registration, as required by
[Apple's thermal notification documentation](https://developer.apple.com/documentation/foundation/processinfo/thermalstatedidchangenotification).
The critical-state response follows Apple's recommendation to reduce optional
work in [Responding to power notifications](https://developer.apple.com/documentation/xcode/responding-to-power-notifications).
No microphone, camera, screen recording or accessibility permission is added.

## Pause ownership

Calm and thermal holds are independent from manual/power pauses and from each
display's **Pause After** interval. While held, decoder playback, the playback
watchdog, duration ticking and desktop-clear replay stand down. The remaining
duration is preserved; a previously expired display stays expired. Adding a
display, replacing media, or updating duration preferences cannot bypass a hold.

A power pause can claim an intended session even when Calm Mode or heat already
holds its motion. On an allowed power resume the session remains held until all
holds clear. Existing power-resume interval behavior is unchanged. Manual Pause
revokes intent, so later hold removal, wake, unlock or power recovery cannot
silently restart playback. Explicit Play is still required.

Status text lists every active reason and explains how to release Calm Mode or
the heat hold. A completed duration or manual pause continues to require Play.

## Validation

Tests exercise thermal entry/recovery boundaries, brief pressure spikes,
interrupted cooling, repeated notifications, persisted opt-in and overlapping
holds. Playback tests cover both orderings of power/hold entry and release, with
manual pause and auto-resume enabled/disabled, as well as independent display
timers, replacements and added/removed displays.

Local validation on 2026-10-11: **327 tests passed, zero failures**, including
real Metal and AVFoundation frame-hold/resume tests. Universal Release builds
passed for **arm64 and x86_64**, including the widget. Native previews checked
the disabled and overlapping-hold settings states and recovery text at the
596 × 455 settings size. App Intents metadata contains both Calm Mode actions.
A separate native menu harness verified that Command–Shift–M toggles Calm Mode
on and off through the actual menu key-equivalent dispatch.
Builds use ad-hoc signing with sandbox entitlements disabled, matching CI.

Physical heat/energy behavior, signed-sandbox Shortcuts discovery, VoiceOver and
real sleep/lock/monitor transitions still require release validation on supported
Macs. Simulated thermal notifications do not establish those hardware results.
