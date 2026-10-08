# First playback and the included sample

The first welcome page offers **Try a sample** and **Import my video** alongside
Skip and Next. Settings > General > Getting Started > Show welcome tour and
sample reopens the same four-page tour without resetting existing preferences.
Opening, cancelling, or closing the tour does not itself mark onboarding complete.

The default target is explicitly **All displays**. A user can choose one connected
display before either action. The target is captured when the operation starts;
disconnecting it produces an error instead of redirecting to another display.
An individual target keeps every other display's wallpaper, including an empty
desktop. Assignments use display UUIDs and library paths so a library rescan does
not lose them. The older name/Wallpaper-ID mapping remains a fallback for existing
installations; already-lost legacy assignments cannot be reconstructed.

Playback continues to respect manual pause and power restrictions. Success means
the wallpaper was applied, not that restrictions were bypassed. Closing the tour
or pressing Cancel prevents a late import from changing the desktop. A copy that
finished importing before cancellation may remain in Library for later use.

## Sample content and ownership

`src/Wallnetic/Resources/Samples/AuroraSample.mp4` is an original procedural
animation generated specifically for this repository by
`tools/generate-onboarding-sample.swift`. It contains two moving mathematical
radial gradients over a solid background, with no external footage, images,
fonts, music, or other third-party assets. The generator and resulting sample
are distributed under the repository's MIT license; retain that license when
redistributing. No additional third-party attribution is required.

The bundled sample is 371,251 bytes, 1280 × 720, H.264, 30 fps, six seconds, and
has no audio. SHA-256:
`4a7864906b337ce698efcb498e3cf41b90702ed1e22de11088c7753a79a5292d`.

It works offline and needs no account or download. No network request is made by
the sample flow, so download progress is inapplicable. The welcome page discloses
the size before installation, displays preparation progress with Cancel, and
offers Import my video if the bundled resource is missing or unreadable.

The bundle remains read-only. Trying the sample adds an ordinary, removable copy
to Library with a unique filename. Repeated attempts reuse only the recorded
copy whose contents still match the bundle; similarly named user files or an
edited copy are not overwritten, deleted, or substituted. The importer limits
sample reads to 2 MiB. Remove the sample using the existing Library removal
action, which also clears any desktop renderer using that file. Trying it again
creates a fresh copy.

To regenerate on macOS, choose a new output path (the writer does not overwrite):

```sh
swift tools/generate-onboarding-sample.swift /tmp/AuroraSample-new.mp4
```

Update the size and checksum above if the asset changes. The automated asset
test enforces the advertised size cap, playability, resolution, duration, and
absence of audio. Other tests cover concurrent/repeated installation, file
preservation, removal/reinstallation, cancellation, target errors, and durable
display assignments. The full local suite passed 219 tests and the universal
Release build passed for arm64 and x86_64. The first page was visually checked
at its 640 × 520 content size. Physical Intel, actual monitor hot-plug, VoiceOver, and
clean-install onboarding on other supported macOS versions remain release checks.
