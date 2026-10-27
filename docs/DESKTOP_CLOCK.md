# Desktop clock

Wallnetic can draw a clock, with an optional date, on each display's live
wallpaper. It is off by default.

## Settings

Settings > Effects > **Desktop Clock**:

- **Show clock**, off by default.
- **Show date**: the weekday, day and month.
- **Position**: Top Left, Top Center (the default), Center, Bottom Left, Bottom
  Center or Bottom Right, inside the display's visible area.
- **Size**: Small, Medium (the default) or Large, relative to the height of each
  display's visible area. On a display too narrow for that size, such as a
  portrait display, the clock gets the largest size that fits.

Changes apply to every display at once and persist across launches. Reset All
Effects does not change them. If the saved preferences cannot be read, the
defaults apply.

## Where it appears

- The clock is drawn inside each display's existing wallpaper window, above the
  video and the wallpaper effects. No window is added, so it shares that
  window's place: below desktop icons and app windows, on every Space, with
  clicks passing through to the desktop.
- A display shows its clock only while its window shows a wallpaper frame.
  Turning the clock on never reveals an empty display, and clearing a display's
  wallpaper removes its clock.
- The clock stays inside the visible area, not under the menu bar or the Dock.
  The default Top Center position avoids the right edge, where Finder places
  desktop icons, and the left edge, where Stage Manager shows its strip.
- Wallpaper effects (brightness, contrast, saturation, blur, tint and vignette)
  never alter the clock on either engine. It is a sibling of the renderer view,
  outside the layer the effects filter.
- The text is white with a soft shadow, drawn into the clock's own image. There
  is no live blur, material or backdrop filter behind it. With Increase Contrast
  or Reduce Transparency on, the image gets a dark backdrop. The image is
  drawn again only when its text, size, position or display scale, or one of
  those two settings, changes.
- Minute changes and showing or hiding the clock are never animated.

## When it hides

Every display's clock hides, and its timer stops, while the display sleeps,
while the session is locked or switched away, and while a screen saver runs. A
display's clock also hides while that display shows no wallpaper frame.

A paused wallpaper keeps its still frame on screen, so its clock stays and keeps
updating. This applies to every pause: by you, by the playback timer, Calm Mode,
heat, battery, Low Power Mode or a fullscreen app. Freezing the clock would show
a wrong time, and hiding it would make it disappear whenever an unrelated
feature pauses playback.

The clock only reads the pause state. It never pauses, resumes or reloads a
wallpaper, and never moves, orders or reveals a window.

## Time and date

- The clock uses the Mac's language, region and 12/24-hour setting, as the menu
  bar clock does. Wallnetic's own text is English only, so macOS gives the app
  English formats for the region (for example English for Turkey on a Turkish
  system). The clock instead formats in the first preferred language, in that
  region, keeping an explicit 12/24-hour choice and the calendar. App copy
  stays English.
- The time shows hours and minutes, never seconds, even when a custom time
  format includes them. The date shows the weekday, day and month in that
  language's order and digits.
- One timer serves every display and fires at each minute boundary. The clock
  also updates at once after the Mac or a display wakes, and after the system
  clock, time zone, day or region changes. While no display shows a clock, there
  is no timer and no observer.
- When a clock appears, for example after waking or unlocking, it already shows
  the current time.

## Not shown

- The lock screen, Mission Control previews and Space-switch animations show the
  still image from
  [System Wallpaper Sync](../README.md#system-wallpaper-still-frame-sync), which
  never includes the clock. Stills still come from the source video, with no
  window capture and no Screen Recording permission.
- The [standalone screen saver](STANDALONE_SCREEN_SAVER.md) has no clock.
- There are no seconds, per-display settings, dragging, custom fonts or colors,
  analog style or menu-bar toggle.

## Accessibility

The clock is decorative. It is not a VoiceOver element and makes no
announcements; the menu-bar clock remains the accessible source. Each Settings
control has a text label for VoiceOver.

## Limits

- When the Dock or the menu bar changes without macOS reporting a display
  change, the clock moves at the next minute change.
- Resource use is not measured yet. No CPU, GPU or energy figure, and no savings
  claim, is made. Measurement follows the [benchmark protocol](PLAYBACK_BENCHMARKS.md):
  isolated-host sessions with `--overlay clock` and without, for Metal and
  AVPlayer, on one display and on two, plus full-app clock-off and clock-on
  sessions for a paused wallpaper.

## Verification

### Automated

`DesktopClockTests` covers:

- the visibility rule for every pause reason, with and without a presented
  frame, on one display and on two;
- minute boundaries, including midnight and DST transitions;
- time and date text for 12- and 24-hour locales, date order, non-Latin digits,
  time zones, day rollover and DST, with injected locales and time zones;
- the clock's locale from Wallnetic's English locale and the preferred
  languages: Turkish, French (Canada), German, Arabic and English systems, and
  an explicit 12/24-hour choice;
- settings defaults, persistence and the fallback for missing or corrupt data,
  with injected `UserDefaults`;
- the scheduler, with an injected clock, timer and notification centers:
  re-arming after each tick, wake, screen wake, system clock, time zone, day and
  locale changes; arming from the time shown, so an update that ends after a
  minute boundary still updates at it; and no timer or observer after it stops
  or after cleanup;
- placement inside the visible area for every position, including a Large
  12-hour clock, with and without the backdrop, on a portrait display with and
  without a side Dock;
- the real window controller with spy renderers on every connected display:
  revealing windows, ticks, showing, hiding, setting changes and status
  refreshes call no renderer method and change no pause reason or playback
  state;
- the view hierarchy: the clock is the last sibling of the renderer view, outside
  it and its filtered layer;
- both engines inside that container: the first frame shows in a window kept at
  alpha 0, and the video follows a window resize (Metal drawable size, AVPlayer
  layer frame).

### Pending physical and VoiceOver checks

None of these has been performed yet:

- Settings with VoiceOver and the keyboard only, and Reset All Effects leaving
  the Desktop Clock settings unchanged.
- Clicks, selection and desktop icons beneath the clock.
- Updates within one minute after changing the region, the 24-hour setting, the
  time zone or the system clock while Wallnetic is inactive. Any change that
  waits until Wallnetic becomes active is to be recorded here as a limit.
- On a system whose primary language is not English, on macOS 13 and on a later
  version: the weekday and month language, the date order and digits, and the
  time with the 24-hour setting on and off, each compared with the menu bar.
- At least ten minute changes, each logged within one second after its boundary,
  for a playing and a paused wallpaper with Wallnetic in the background.
- The current time on first appearance after waking, unlocking, returning from
  fast user switching and leaving the screen saver.
- The first frame and full-screen video on both engines inside the new window
  content: no empty or black window before the first frame, and correct video
  size after a resolution change and a scale change.
- Effects on both engines; readability over light and dark videos with Increase
  Contrast and Reduce Transparency each on and off; no animation with Reduce
  Motion on and off.
- The multi-display matrix: different scale factors and a scale change,
  hot-plug and removal, resolution and arrangement changes, mirroring, Dock and
  menu-bar changes, "Displays have separate Spaces" and Stage Manager on and off,
  and Space switches without re-creating, reordering or flashing the clock.
- VoiceOver through at least three minute changes with Wallnetic active, with
  Settings open and with Finder frontmost: no announcement and no focus.
- The resource sessions listed under Limits.
