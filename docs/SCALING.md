# Scaling: Fill and Fit with Blurred Backdrop (#348)

A wallpaper's video rarely has the display's exact shape. Each wallpaper has
a scaling choice that says what happens then.

| Choice | What it does |
| --- | --- |
| **Fill** (default) | Covers the display and crops what does not fit. |
| **Fit with Blurred Backdrop** | Shows the whole frame. The rest of the display shows a blurred, dimmed copy of the same frame. Nothing is cropped and there are no black bars. |

Choose it from a wallpaper's context menu: **Scaling**.

## Behavior

- The choice is saved per wallpaper, by file path, on this Mac. Removing a
  wallpaper from the Library removes its choice.
- A change shows at once on every display playing that wallpaper, also while
  playback is paused. It does not restart the video, so Pause After, Calm
  Mode and Trim carry on.
- A video that already has the display's shape (within half a percent) is
  simply filled, since there is nothing to fill around it.
- Wallpaper effects and the Desktop Clock apply to the finished picture, in
  both choices. The still image synced to the system wallpaper is unchanged.

## How it is drawn

The Metal renderer draws the backdrop from the frame it already has. No
second player or decoder runs.

1. The aspect-filled frame is shrunk into a small offscreen texture, 256
   pixels on its long side.
2. That texture is blurred there with two rounds of a 9-tap Gaussian.
3. The drawable gets the blurred texture, dimmed, over the whole view, then
   the whole frame centred on top.

Blurring at a small size keeps the extra work low and hides the low
resolution.

## Limits

- **AVPlayer renderer.** It always fills. Its video layer cannot be drawn a
  second time, so the Scaling menu is offered only with the Metal renderer.
- The backdrop's blur and dimming are fixed.
