# Loop range (Trim)

Trim chooses which part of a Library video the wallpaper loops: a Start frame
and an End point. The original file is never modified or re-encoded, and no
second file is created.

## Choosing a range

- In the Library or on Home, Control-click a video and choose **Trim…**.
  Trimmed videos offer **Edit Trim…** and **Remove Trim** instead.
- The sheet loops a muted preview of the selection. Set **Start** and **End**
  with the sliders, or move either by one frame with its stepper. Both work with
  the keyboard and VoiceOver, which reads each time and the loop length.
- A loop is at least one second long. Selecting the whole video stores no trim;
  **Reset to Full Video** returns to it.
- **Save** stores the range. **Cancel**, or closing the sheet, keeps the range
  stored before.
- If the video leaves the Library, or its file changes while the sheet is open,
  Save stores nothing and says why.

## Playback

- Both engines (Metal and AVPlayer) play only the selected range, through a
  passthrough composition of the original file. This applies on every display
  showing the video, including after a wallpaper switch, Retry or a newly
  connected display, and to automatic changes from playlists, daily schedules,
  weather and Space recovery.
- Saving, editing or removing a range updates the displays showing that video
  without reselecting it. Displays showing other videos do not reload.
- An edit never resumes a pause by any owner: manual, power or fullscreen
  rules, Calm Mode, thermal holds or Pause After. A paused display keeps its
  frame and reads Paused; the new range takes effect when it resumes. A running
  Pause After interval keeps its deadline.
- Pause After starts a trimmed wallpaper's interval at its Start frame.
- Each wrap returns to Start. When Start is not a keyframe, decoding begins at
  the keyframe before it; the seam is measured with the
  [benchmark protocol](PLAYBACK_BENCHMARKS.md), not assumed.

## When a range does not apply

The full video plays instead of a failed or black wallpaper, and the Library
card reads **Trim not applied**, when:

- the file changed since the range was saved (a different size or modification
  date), for example a different video imported under the same name; or
- the range no longer fits the video's length.

The engines also play the full video when a trimmed asset cannot be built.

## Storage

Ranges are saved on this Mac as versioned data keyed by the file's path, like
[Pause After](PAUSE_AFTER.md) overrides. They are not synced through iCloud and
do not follow a file renamed outside Wallnetic. Removing a video from the Library
removes its range; a failed removal keeps it. If saved ranges cannot be read,
none apply, and the next edit keeps the unreadable data as a backup instead of
discarding it.

## Not affected by a range

- Library and widget thumbnails and the dominant color still come from the start
  of the file.
- Duration labels, filters and sorting outside the Library (Home, Explore,
  Popular and Dynamic Island) still use the full length. Library cards, details
  and the preview show the trimmed length, for example "0:42 of 1:10".
- The system wallpaper still image and optimized copies do not follow the range
  yet.
- Trim does not crop or reframe the picture. Wallpapers always fill the display
  with a centered crop.
