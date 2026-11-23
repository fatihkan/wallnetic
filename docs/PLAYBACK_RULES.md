# Playback rules (#350)

Settings > Playback > **Playback Rules** adds five optional rules. Each is off
by default and works on its own.

| Rule | Pauses while | Continues when |
| --- | --- | --- |
| Pause while chosen apps are in front | one of the chosen apps is the frontmost app | another app comes to the front |
| Pause while chosen apps are running | one of the chosen apps is running | the last of them quits |
| Pause when the Mac is idle | the keyboard, mouse and trackpad have been left alone for the chosen time (1 to 30 minutes) | any key press, click or pointer movement |
| Pause on low battery | the Mac is on battery below the chosen level (10% to 50%) | it is plugged in, or charges to that level |
| Play only on the display in use | another display has the pointer or the active window, for the displays that have neither | the pointer or the active window comes to that display |

## How a rule pauses

A rule that applies is a **hold**, like Calm Mode and the thermal hold. A
hold stops motion and keeps the still frame on screen.

- It never changes the user's own Play or Pause. A manual pause stays paused
  when a rule ends, and playback the user started comes back when it ends.
- Releasing one hold never releases another.
- Play is unavailable while a hold is active, as with Calm Mode.
- A Pause After interval does not count the time a hold lasted.
- The menu bar and Home name the reason, for example "Paused while the Mac is
  idle". The order of reasons is in `PLAYBACK_STATUS.md`.

"Play only on the display in use" holds single displays. A display counts as
in use for 10 seconds after the pointer and the active window left it, so
moving between displays does not flicker. The rule does nothing with one
display, and it never pauses every display.

## What the rules read

Public APIs only. No rule asks for Accessibility, Input Monitoring, Screen
Recording or any other permission.

| Value | Source |
| --- | --- |
| Frontmost and running apps | `NSWorkspace`, with its activate, launch and terminate notifications |
| Idle time | `CGEventSource.secondsSinceLastEventType` for the session |
| Battery state and level | IOKit power sources |
| Display in use | the pointer location, and the bounds and owner of the frontmost window from the window list |

App changes arrive as notifications. Idle time, the battery level and the
pointer are read on a timer that runs only while a rule needs it: every 2
seconds for the idle and display rules (every half second while the idle hold
is active, so input continues playback at once), and every 30 seconds for the
low battery rule alone.

## Limits

- Apps are matched by bundle identifier. An app without one cannot be chosen.
- The idle rule counts any input in the login session, in every app.
- The low battery rule adds to "Pause when on battery power"; it does not
  replace it.
- A wallpaper set on a display that the display rule holds shows its first
  frame when that display is used.
