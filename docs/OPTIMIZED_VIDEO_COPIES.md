# Optional optimized video copies

Choose **Create Optimized Copy…** from a Library/Home wallpaper's context menu. Nothing is converted until **Create copy** is selected. The source file stays untouched, the desktop is not changed by conversion, and the result becomes a separate Library item. The result screen offers original/copy previews, exact byte-size comparison, and explicit apply buttons. An optimized item's context menu can switch back to its source while that source remains in Library. Either item can be deleted independently through normal confirmed library cleanup.

## Presets and tradeoffs

| Preset | Codec | Resolution ceiling | Frame-rate ceiling |
| --- | --- | --- | --- |
| Compact | H.264 | 1280×720, or 720×1280 portrait | 15 fps |
| Balanced | H.264 | 1920×1080, or 1080×1920 portrait | 30 fps |
| HEVC | HEVC | 1920×1080, or 1080×1920 portrait | 30 fps |

Smaller or slower sources are not enlarged or sped up. Dimensions are rounded down to even pixels. Orientation/mirroring is applied to the output pixels, leaving an identity output transform. The source's timeline is retained while the composition samples fewer frames; playback speed is unchanged. Audio is omitted from these wallpaper copies.

HEVC is offered only when VideoToolbox reports hardware encoding and decoding support for the output dimensions and AVFoundation accepts the asset/preset/file-type combination. This is a capability check, not a guarantee about every internal encoder decision. H.264 remains the fallback choice. Apple documents [export preset compatibility](https://developer.apple.com/documentation/avfoundation/avassetexportsession) and [encoder capability queries](https://developer.apple.com/documentation/videotoolbox/vtcopysupportedpropertydictionaryforencoder(width:height:codectype:encoderspecification:encoderidout:supportedpropertiesout:)).

This implementation accepts single-track, finite videos up to 24 hours, with SDR Rec.709 or incomplete color tags. Missing color tags are treated as SDR Rec.709 with an explicit warning. HDR, other color-tagged/wide-gamut formats, alpha/transparency and anamorphic pixels are rejected with an explanation. This avoids promising HDR preservation or silent tone mapping; [Apple's HDR export guidance](https://developer.apple.com/videos/play/wwdc2020/10010/) treats color primaries, transfer functions and matrices as part of that workflow. Recompression is lossy: compare detail, smoothness and color before using a copy.

File-size, CPU and energy savings are not guaranteed. AVFoundation controls bitrate within the chosen native codec preset; a copy can be larger than its source. That outcome is reported on the result screen rather than hidden or automatically applied.

## Lifetime, storage and recovery

- One conversion can run at a time. Native AVFoundation encoding runs asynchronously; progress updates leave the UI responsive. Cancelling or closing the owning sheet requests cancellation and waits for export completion before removing its partial output.
- Start/cancel is serialized, including cancellation immediately before the export begins. The UI stays busy while cancellation is being cleaned up.
- Disk-space preflight requires the larger of AVFoundation's estimate or a conservative 20 Mbit/s duration estimate, plus 128 MiB headroom. Encoder scratch files are directed to the same library volume. A disk-full error during conversion is also recognized and explained.
- Output is created inside a unique hidden `.optimization-UUID` directory under Library, which normal library scanning ignores. Source size, modification date and file identity are checked again before publication.
- Completed output must have the requested codec, dimensions, frame rate, identity transform, SDR color tags and duration within one output frame of the source. Verification failure or cancellation removes the staging directory. Cleanup failure is reported explicitly, including that temporary files remain; originals are never deleted as recovery.
- A verified output moves to a unique final filename on the same volume. There is no suspension between the final cancellation check, publication and relationship recording. Failed relationship writes roll back the unpublished final copy. Source/copy relationships use versioned JSON; unreadable previous data is backed up on the next successful record.
- A force quit or system crash can leave a hidden staging directory. Automatic deletion of another process's staging directories is intentionally avoided. Such an interrupted directory can be removed manually after confirming that no conversion is running.
- No shell command, external transcoder, network request, dependency or entitlement is added by this feature.

## Validation and local measurements

The test suite adds real H.264 conversion, portrait orientation and timestamp-matched SDR image comparisons; HEVC export runs when the test machine has compatible hardware (otherwise that one test is skipped). Additional tests cover no upscaling, fractional frame rates, malformed geometry/color tags, insufficient disk space, disk-full error classification, missing/changed input, conversion failure, cancellation including native export, concurrent-job rejection, output verification, independent deletion relationships and UI lifecycle. Existing library deletion and playback pause tests remain in the full suite.

On 2026-10-09, Apple M4 / macOS 26.6.2, a local native harness converted the existing synthetic 1920×1080 60 fps, 12-second SDR test clip. The source was 12,070,379 bytes. Duration stayed 12 seconds for all three outputs.

| Output | Bytes | Export wall time | Process CPU time during export |
| --- | ---: | ---: | ---: |
| Compact, 1280×720 / 15 fps | 5,898,844 | 0.72 s | 0.20 s |
| Balanced, 1920×1080 / 30 fps | 13,108,566 | 1.63 s | 0.32 s |
| HEVC, 1920×1080 / 30 fps | 12,023,286 | 1.73 s | 0.34 s |

A separate playback phase used one 960×540-point window, Quality mode, a two-second warmup and a five-second sample per case. Playback rate stayed 1.0 in both engines. Process CPU was measured with `getrusage`, as a percentage of one core.

| Source/copy | AVPlayer CPU | Metal CPU |
| --- | ---: | ---: |
| Original | 2.27% | 6.78% |
| Compact | 0.90% | 4.93% |
| Balanced | 1.58% | 5.52% |
| HEVC | 1.39% | 5.62% |

These are short, single-run observations with the Debug app module loaded by an optimized harness. Other apps and the installed Wallnetic remained running. They exclude WindowServer, encoder service processes, GPU/power measurements and battery life. They are not representative energy benchmarks or fixed savings claims. Native option/result sheets and exported SDR frames were visually inspected; automated frame comparisons check matching timestamps and portrait orientation.

**Remaining acceptance work for #254:** representative physical Intel and broader Apple Silicon resource/visual-quality checks, including HEVC-unavailable Intel behavior. A universal arm64/x86_64 build verifies compilation only. Signed-sandbox lifecycle, VoiceOver and longer varied-content playback checks also remain in release validation. Keep the hardware acceptance checkbox and issue open until those measurements are completed.
