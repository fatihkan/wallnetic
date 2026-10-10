# Space selection recovery

Implemented on `dev` for #256. This is a development change, not a claim about the currently published 1.4.2 build.

## Behavior

Settings → Spaces saves named wallpaper choices for manual recovery. Existing assignments migrate into this list, including choices whose media is missing. Use **Edit** to name a choice or select another Library item, and **Apply** to use available media without importing it again. The Library context menu offers **Save for Space Recovery**; saving alone never changes playback.

Applying a choice uses the normal manual wallpaper action on **all displays and Spaces**. It does not assign a wallpaper exclusively to one desktop. Desktop windows use `.canJoinAllSpaces`; the UI and README now say so. An enabled daily schedule or playlist holds the manual choice for 30 minutes through the existing manual-override mechanism. Other normal playback/power controls still apply.

The former Dock/Finder window-number sum and six numbered desktop rows are removed. Window numbers can change and collide; neither their sum nor the order of observation proves a desktop identity. Previously persisted numeric keys, including old index keys, are treated only as saved user choices. No assignment is automatically matched or applied.

## Supported API investigation

- [`NSWorkspace.activeSpaceDidChangeNotification`](https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification) reports a Space change and has no `userInfo` payload containing an identifier. Observe it on the workspace notification center.
- [`NSWindow.isOnActiveSpace`](https://developer.apple.com/documentation/appkit/nswindow/isonactivespace) describes a particular window's relationship to the active Space. It supplies no durable desktop ID. We do not turn a window probe into a claim of persistent desktop identity.
- [`NSWindow.CollectionBehavior.canJoinAllSpaces`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces) permits a window to appear in all Spaces. This is the existing wallpaper overlay behavior.

Engineering conclusion: these supported APIs do not establish a persistent identity suitable for the existing saved assignments. The safe fallback is explicit manual recovery. No private CGS/SLS calls, Dock database inspection, Accessibility automation, screen recording, shell commands, network access, new dependency or entitlement is introduced.

## Restoration matrix

| Scenario | What survives | Safe behavior |
|---|---|---|
| Library rescan | Selection UUID, name and media path | Resolve the same local Library path despite new transient wallpaper UUIDs. |
| App relaunch / reboot | Selection list | Start with **Needs reassignment**; never restore a Space binding or apply automatically. |
| Active Space changes | Selection list | Clear the manual-application acknowledgement; report the change; no automatic playback. |
| Space creation, removal or reordering | Selection list | No mapping to become stale. A Space-change notification clears acknowledgement when delivered. Without a notification no topology detection is claimed; acknowledgement is only historical, never a verified binding. |
| Monitor connection, removal or reconfiguration | Selection list | Screen-parameter notification requires recovery; never map display identity to Space identity. |
| Sleep/wake or user-session switch | Selection list | Clear acknowledgement; require explicit application again. |
| Media temporarily missing | Name and path | Keep the row; disable Apply; allow a Library replacement. |
| Media explicitly deleted through Library | Name and selection UUID | Clear the deleted path and allow replacement; do not reimport or resurrect it. |
| Space recovery disabled | Selection list | Stop observers and refuse recovery playback. Editing saved choices remains possible. |

The acknowledgement **Applied manually · no desktop binding** records a user action; it is not a live claim about the current wallpaper or desktop identity. Schedules and other manual actions can change playback independently. This feature does not suppress the ordinary app-wide wallpaper restoration on launch.

## Persistence and safety

- Versioned `spaces.selections.v1` stores records, not Space IDs. A record UUID belongs only to Wallnetic's saved choice.
- Migrate every legacy `spaces.assignmentsJSON` value once; retain the legacy JSON unchanged for recovery. Keys such as `1` and `01` cannot collide because no integer-key dictionary is constructed. An empty new document prevents deleted selections from returning on a later launch.
- Unreadable, duplicate-ID, oversized or future-version documents block mutation. **Start a new list…** requires an in-app confirmation, keeps the unreadable document under a unique backup key, and starts an empty list. Invalid legacy JSON remains at its original key.
- Apply requires an enabled feature, a matching current Library item, a local file URL, and an existing file. A saved path alone does not authorize arbitrary file loading, network access or import. No media is deleted by removing a saved choice.

## Validation

Automated coverage in `SpaceWallpaperRecoveryTests` exercises legacy-key collisions, one-time migration, relaunch, manual-only application, notification-driven invalidation, observer lifetime, rescan identity, unavailable/network/out-of-library media, replacement, deletion, disabled recovery, malformed/future data and invalid edits. Tests use isolated defaults and injected notification centers/application callbacks; they do not switch the user's real desktops or wallpaper.

Local validation on 2026-10-10: the full suite passed **303 tests, zero failures**. After final review adjustments, all **19 Space recovery tests** passed again. Universal Release compilation succeeded for **arm64 and x86_64**, including the widget. Native previews at the 596 × 455 settings size covered available/missing choices, manual-application acknowledgement, editing and unreadable settings. Build/test runs used ad-hoc signing with entitlements cleared and sandbox disabled, matching CI; they are not signed-distribution validation.

Physical release checks remain required on supported Macs: quit/relaunch and reboot, create/remove/reorder Spaces, separate Spaces per display on/off, real monitor hot-plug, sleep/wake, VoiceOver, and the signed sandbox build. Simulated notifications and CI builds do not establish those hardware results. Keep #256 open until its physical lifecycle criterion is verified.
