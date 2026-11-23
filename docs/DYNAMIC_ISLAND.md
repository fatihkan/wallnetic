# Dynamic Island (#352)

The Dynamic Island shows the current wallpaper and a few controls at the top
of every display. It is off by default: Settings → General → Dynamic Island.

- **On a display with a notch** it is part of the notch: a black bar of the
  notch's height that reaches 44 points past it on each side, with a flat top
  and concave ears that flow into the screen's top edge.
- **On any other display** it is a pill that floats 6 points below the menu
  bar.

## What it shows

| State | Content |
| --- | --- |
| Compact | The wallpaper's thumbnail on the left and the playback state on the right: playing, paused or Calm Mode. The floating pill also shows the wallpaper's name. |
| Expanded | The wallpaper's name, the display and the playback state. Controls: play or pause, next wallpaper, Calm Mode, the playback profile (a click moves to the next one) and Open Wallnetic. |

A video file dropped on the island is imported and set as the wallpaper.

Rename, favorite, shuffle and previous are no longer on the island. Rename
and favorite are in a wallpaper's menu in the app; previous and random are on
the global hotkeys.

## Opening and closing

- **Hover opens it; leaving closes it** after 0.6 seconds. There is no click
  to toggle, because a pointer always hovers before it clicks.
- It opens by itself for a moment when the user changes the wallpaper. It does
  not do so for automatic changes (playlist, schedule), and **not within 3
  seconds of a key press**, so it never opens over someone who is typing.
- **It steps aside while an app is in full screen** and comes back afterwards.
- It closes by itself after 8 seconds if a pointer exit was never delivered.

## The shape

The shape is a signed-distance field drawn in one small Metal pass
(`Engine/IslandSurfaceView.swift`). The numbers come from
`Models/IslandGeometry.swift`.

- **Two rounded rectangles joined by a smooth union:** the bar (or pill) and
  a card. While compact, the card rests inside the bar. To expand, the card
  pushes out through the bar and the seam between them is rounded over 14
  points, which is what reads as liquid.
- **At rest the shape is exact.** Two shapes whose edges lie on each other
  would swell there, so the blend fades out as the card reaches full size.
- **A spring** (0.38 s, damping 0.74) drives the stretch. It passes its target
  by about 3 percent and comes back.
- **The ears** on a notch display are a smooth union with the screen's top
  edge.
- **The glow** around the island takes the wallpaper's accent colour. It is
  kept off the menu bar on a notch display.

The window does not animate. It takes the expanded size before the shape
grows and returns to the compact size after the shape has shrunk, so only
the area of the shape (plus 18 points for the glow) ever takes clicks.

The surface and the content inside the window always have the expanded size
and hang from the window's top centre. A change of the window's size moves
them and draws nothing. (When they were sized to the window, a frame drawn
for the old size could stay on screen, stretched, with the content beside the
shape.)

## Drawing on demand

The surface draws a frame only when the shape, the colours or the window's
size change. A timer runs the spring while the shape moves and is removed
when the spring rests. **A resting island draws nothing.**

If Metal is not usable, the island draws a plain rounded rectangle and keeps
working.

## Accessibility

| Setting | Behaviour |
| --- | --- |
| Reduce Motion | No stretch. The card is drawn at full size and fades in or out in 0.18 seconds. |
| Increase Contrast | A solid black fill with a light outline, and no glow. |
| VoiceOver | The compact island reads the playback state. Every control has a label. |

## Looking at it without a pointer (debug builds)

Launch arguments:

| Argument | Effect |
| --- | --- |
| `-island.enabled YES` | Turns the island on. |
| `-island.debugExpanded YES` | Keeps it open. |
| `-island.debugProgress 0.5` | Holds the shape between compact (0) and expanded (1). |
| `-island.debugCycle YES` | Opens and closes it every two seconds. |
| `-island.debugNotchWidth 200 -island.debugNotchHeight 32` | Draws the notch variant on a display without a notch. |
| `-island.debugReduceMotion YES` | Stands in for Reduce Motion. |
| `-island.debugIncreaseContrast YES` | Stands in for Increase Contrast. |

## Verification

### Automated

`IslandGeometryTests` covers:

- the pill and the notch bar, the expanded card, and the window's frame and
  anchor for both kinds of display;
- that a resting shape is exactly the bar or the card, that the card grows
  steadily, and that overshoot is bounded;
- the spring (it reaches the target, passes it a little, rests, and survives
  a late frame) and the Reduce Motion fade;
- the rules: no opening by itself after a key press, and stepping aside for
  a full-screen app;
- that the shader compiles, and that the surface draws once per change and
  not at all for the same shape again.

### Seen on a Mac

On a Mac mini with an external display (1x, 144 Hz, macOS 27), with only the
island's own window captured:

- the floating pill, the expanded card and held shapes in between;
- opening and closing by itself: the window grows first, the shape stretches
  and passes its target (368 points wide before it rests at 364), and the
  window shrinks after the shape has;
- the notch variant with a simulated notch: the flat top, the ears and the
  card below the notch;
- the Reduce Motion fade and the Increase Contrast outline, through the debug
  arguments.

### Not checked

- **A real notch.** Whether the bar meets the hardware notch without a seam,
  in a light and in a dark menu bar, needs a MacBook.
- Hover with a real pointer, the controls' clicks, and dropping a file.
- Stepping aside for a full-screen app, and staying closed while typing,
  on a live system. Their rules are unit tested.
- Reduce Motion and Increase Contrast switched on in System Settings.
- Two displays of different kinds at once, a 2x display, an Intel Mac, and
  macOS 13 to 26.

## Credits

The idea of an island that flows out of the notch comes from
[Liquid Notch](https://github.com/fellipegoncalvesleite/liquid-notch) (MIT).
No code or shader from it is used here, so no notice is carried.
