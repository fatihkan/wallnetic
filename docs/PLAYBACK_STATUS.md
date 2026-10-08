# Playback status

The menu bar lists a status for each connected display. Open that display's
submenu for the explanation or retry action. Settings > Displays shows the same
status beside its wallpaper controls. The menu also shows the saved playback
profile; it does not imply a decoder or CPU limit for the AVPlayer fallback.

Statuses distinguish no selection, loading, playing, waiting for video, paused,
and an unavailable selection. Playing requires a presented frame and the
player's playing state. Merely requesting Play does not satisfy that condition.
The existing global Play/Pause control still governs playback intent, including
pending loads; these display snapshots do not change power-pause ownership.
If a pause condition arrives before the player actually stops, the observed
Playing state remains visible with those conditions in its detail. A policy
change alone is not evidence that the renderer has stopped.

## Pause explanations

The deterministic priority is manual pause, inactive/locked session, sleeping
display, screen saver, Low Power Mode, battery policy, fullscreen restriction,
desktop coverage, then expiration of the playback timer. Additional active
reasons remain in the detail. File failures take precedence so the recovery
action remains visible, while pause reasons are retained alongside it.

The menu's Play action is disabled while a displayed restriction blocks resume.
The existing controller also checks restrictions for keyboard shortcuts, widgets,
and other playback entry points. Clearing one reason does not clear another.
The coverage reason reflects the existing visibility policy; this feature does
not introduce a new coverage detector or change which windows pause playback.

## Loading and recovery

A missing/inaccessible or unplayable file, asset-load error, or failed player
item produces an unavailable status. Retry reloads the assigned file only on the
selected connected display. It preserves manual pause, current power restrictions,
and a power pause whose automatic resume was disabled. Restore a missing file or
choose a different wallpaper when retry cannot resolve it.

A failed replacement preserves the previous video's existing loop and frame.
The status describes the failed selection and explains that a previous wallpaper
may remain visible. Neither its old frames nor late callbacks from an earlier
load can turn the failed selection into a successful status.

## Observation and accessibility

AVPlayer item/time-control observations, first-frame events, playback commands,
existing power events, preferences, and display changes update value snapshots.
Equal states are discarded. There is no new polling timer. Observations are
invalidated on replacement/stop and display removal; queued callbacks are checked
against their load generation. Observation never issues playback commands.

Native menu items, text, symbols, and explicitly named retry buttons communicate
the state without relying on color. Screen labels identify which display an
action affects. Full explanations are visible in Displays settings as well as
the menu; they are not available only through pointer hover.

## Validation

The local suite passes 210 tests, including every pair of pause reasons, distinct
display snapshots, loading/waiting/playing states, recovery guidance, deduplicated
events, stale callback rejection, and real AVPlayer/Metal failure-to-retry flows.
Renderer tests also retain coverage for failed replacement loops, duration pauses,
performance profiles, and normal playback speed.

Light/dark status views were rendered and visually inspected. Manual VoiceOver
navigation, native menu interaction across supported macOS versions, physical
Intel playback, and actual lock/sleep/hot-plug scenarios remain release checks.
