# Preview before applying (#349)

**Preview…** in a wallpaper's context menu opens a sheet that plays the
wallpaper the way a display would show it. The desktop does not change until
the user applies it.

## What the preview shows

The stage is drawn by the same code as a display's wallpaper window:

- the renderer in use (Metal or AVPlayer) and the current playback profile;
- the wallpaper's loop range (Trim);
- its scaling, Fill or Fit with Blurred Backdrop;
- the current wallpaper effects;
- the Desktop Clock, when it is turned on in Settings, placed inside the part
  of the stage that stands for the display's visible area.

The stage has the shape of the chosen display. With several displays, a
**Display** menu picks which one.

## Controls

| Control | What it does |
| --- | --- |
| Pause Preview / Play Preview (Space) | Pauses or plays the preview only. |
| Display | The display whose shape is shown, and the target of "Apply to…". |
| Scaling | A draft. It is saved with the wallpaper only when it is applied. Offered with the Metal renderer. |
| Apply to All Displays / Apply (Return) | Saves the draft and sets the wallpaper on every display. |
| Apply to *display* | Saves the draft and sets the wallpaper on that display only. The app switches to Different per display, and the other displays keep what they show. |
| Close (Esc) | Discards the draft. The desktop stays as it was. |

## Behavior

- One extra player runs while the sheet is open. Closing or applying stops it.
- The preview pauses while the app is hidden or its window is minimized, and
  resumes when it is shown again.
- With Reduce Motion on, the preview shows the first frame and waits for Play.
- VoiceOver reads the stage as "Preview of *name* on *display*", with Playing
  or Paused as its value.

## Notes for maintainers

- `WallpaperPreviewStage` owns the renderer and a `DesktopClockCoordinator`
  whose geometry is the stage, not a screen.
- A Metal view that joins a window through a sheet was left with a layer
  scale of zero: it presented frames and showed nothing. The stage sets the
  layer's scale from its window after each layout.
- Effects are applied when the sheet opens. A change made in Settings while
  the preview is open shows the next time it opens.
