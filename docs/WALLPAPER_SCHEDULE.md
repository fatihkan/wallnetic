# Daily schedules and timed playlists

The Schedule settings page provides a local-time, 24-hour timeline. Drag a bar to move it without changing its length, drag either handle to resize it in five-minute steps, or choose Edit to enter exact `HH:mm` values and select a wallpaper. The named Edit buttons and time fields provide an alternative to dragging.

## Daily range rules

- Start times are inclusive; end times are exclusive. Adjacent ranges are allowed.
- An end earlier than the start crosses midnight. `00:00–24:00` covers the entire day. Equal start and end times are rejected.
- Overlapping ranges and invalid times are rejected before saving. The last valid schedule stays in use. Up to 96 ranges can be stored.
- Gaps and missing/unassigned wallpapers leave the current wallpaper in place. The settings page explains the fallback. Library cleanup keeps the range and clears its removed wallpaper selection.
- The schedule follows the current local clock, including timezone changes. During a spring DST jump, nonexistent minutes are skipped. During the autumn repeat, both occurrences of a local time use the same range.
- Wake, screen wake, timezone/clock changes, and launch trigger reevaluation. Missed transitions are not replayed. Normal evaluation happens at minute boundaries.

## Playlist rules

The existing Whole Library, Favorites, and Collection modes retain their source, collection, order and common interval. Enabling **Set a duration for each item** initially copies the selected source into an editable list using that common interval. Each item can then be changed, moved up/down or removed independently. Switching back retains both configurations.

- Individual durations accept 1–86,400 seconds; up to 500 custom items are supported. Large source-based lists remain supported. Enabling custom durations for a source above that limit reports an error without truncating the source or changing modes.
- Custom items play in the displayed order, then repeat. Source Shuffle creates a shuffled cycle and persists its order; starting again creates a new cycle.
- A persisted cycle start selects the current item directly. Sleep, manual holds and time while the app is closed count toward elapsed time. Timezone changes do not affect durations. Forward clock adjustments advance the cycle; a clock adjustment before the saved start begins a fresh cycle.
- Editing duration, order, source or items begins a new cycle. Explicitly enabling the playlist also starts a new cycle. Relaunch restores the saved cycle.
- Missing custom items are visibly marked and skipped. The effective cycle contains only available items; availability changes can change its current position. If no items are available, the current wallpaper is kept. Removing a library file retains its custom item as an unassigned placeholder.
- The cycle measures elapsed time, independently of video loading or playback pauses. It does not grant permission to resume manually paused or power-paused playback.

## Manual choice and automation priority

Daily scheduling and playlist rotation are mutually exclusive. Enabling either stops the other and makes it take priority over automatic weather changes. Weather callbacks cannot overwrite the active schedule, including during gaps or manual holds. After scheduling is disabled, weather can apply on its next normal condition change. Space selections now use [explicit manual recovery](SPACE_RECOVERY.md), with the same 30-minute manual hold; Space changes never automatically apply a selection.

A manual wallpaper choice, including a choice for one display or a display mode change, defers the enabled schedule/playlist for 30 minutes. A later choice extends that deadline. The deadline survives relaunch, and **Resume schedule/playlist now** ends the hold immediately. A playlist's cycle continues during the hold; resuming selects the item at the current elapsed position.

Scheduled changes apply to all displays in Same mode through the normal playback path. Existing power and manual pause ownership continues to control whether the wallpaper plays. Per-display assignments remain available for returning to Different mode.

At launch, automation starts after the saved wallpaper and playback delegate have been restored. If both legacy enable flags are set, the last explicitly selected mode wins; without an owner record, the daily schedule wins.

## Saved settings and migration

The four existing time-of-day entries migrate once to versioned JSON ranges, preserving their paths and valid start hours. Invalid or non-increasing hours fall back to 06:00/12:00/17:00/21:00 with a visible notice; all four selections and the original legacy settings are retained. The new editor does not rewrite the old keys.

Playlist legacy keys remain intact. Individual items and playback progress use separate versioned JSON documents. Reads and writes are bounded to 1 MiB per document; validation checks versions, IDs, times and durations. A failed read leaves the original settings intact. An explicit replacement retains a `.recoveryBackup` copy before saving. Only files already present in the wallpaper library can be scheduled; the feature adds no network access, executable commands, permissions or external dependencies.

## Validation

`WallpaperScheduleTests` covers boundaries, overlap rejection, overnight moves, DST transitions, timezone reevaluation, migration, missing/deleted files, manual holds across relaunch, unequal durations, long offline periods, shuffled cycle restoration, conflicting legacy flags, large source lists, and corrupt-data recovery. Runtime tests exercise clock/timezone/day/wake notifications and observer cleanup. Existing pause-ownership tests cover wallpaper changes while manually or power paused.

Before an App Store/DMG release, include real sleep/wake, system timezone changes, VoiceOver/keyboard interaction with the timeline editors, multiple physical displays, and signed sandbox migration in the release-wide device checks. Unit tests simulate clocks and lifecycle notifications; they do not replace those hardware checks.
