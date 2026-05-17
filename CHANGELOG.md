# Changelog

All notable changes to Wallnetic are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.3.0] — 2026-05-17

> First release on the v1.3 track. Bundles the entire May development cycle
> (#129 → #204): new Photos slideshow generator, App Store hardening (sandbox
> + privacy manifest), full Light theme support, Dynamic Island multi-monitor,
> security + performance sweeps, and the new design language (Liquid Glass
> polyfill + ambient stage + theme-aware Surface tokens).

### Added
- **Photos slideshow generator** (#137): Create wallpapers from your Apple Photos
  library. Multi-select grid, Ken Burns pan/zoom, crossfade transitions, three
  resolution presets (1080p / 1440p / 4K), 50-photo cap.
- **Battery prompt with override toggle** (#172): When the Mac switches to battery
  (or launches on battery), users see a prompt offering to keep the live wallpaper
  running. New `Playback → Always play on battery` Settings toggle makes the
  choice permanent; `Reset battery prompt` brings the dialog back.
- **Global hotkeys**: `⌘⇧→` next, `⌘⇧←` previous, `⌘⇧P` play/pause, `⌘⇧R` random.
- **Light theme support** (#202, #203): Full System / Light / Dark appearance
  modes. New `Surface` design-token palette (11 tokens) with `NSColor` dynamic
  providers tracks `NSApp.appearance` in real time across all main views,
  settings panes, sheets, top navigation, and tab content. Liquid Glass surface
  fills, lensing strokes, and grain overlay all adapt to the active mode.
- **Dynamic Island on every display** (#201): When more than one monitor is
  connected, the island renders on each screen with a shared expand/collapse
  state. Hot-plug observer (`NSApplication.didChangeScreenParametersNotification`)
  adds/removes panels as displays are attached, detached, or mirrored.
- **2026 design language (Liquid Glass + ambient stage)** (#187 → #198): A new
  cinematic chrome built on stable APIs — `.regularMaterial` blur layered with
  accent gradient, lensing strokes, inner highlight ring, and multi-layer
  shadows. Concentric-radius scale (`Radius.window` → `Radius.accent`),
  4-pt spacing grid (`Space`), and a tracked typography scale (`Typo`).
- **DynamicAccent**: Window-wide accent color derives from the active wallpaper's
  dominant tone, threaded through the SwiftUI environment so every chrome
  surface re-tints when wallpapers change.
- **AmbientStage**: Drifting accent radial + cursor spotlight + vignette
  applied once at the window root; rasterized grain overlay defeats SwiftUI's
  8-bit gradient banding.
- **Cinematic onboarding** (4 steps): Animated gradient orbs per step, glow
  blob, sequential title/kicker/description reveal, capsule progress.
- **3D perspective wallpaper carousel** (#127): New Carousel3DGallery component
  with rotation3DEffect + scaleEffect tied to scroll position.
- **SQLite metadata cache** (#115): Local SQLite index (libsqlite3, no SwiftPM
  dep). Wallpaper title/tag search routes through this index for libraries
  with more than 200 entries, with the in-memory store as a fallback.
- **Privacy Manifest** (#164): `PrivacyInfo.xcprivacy` declares required-reason
  APIs (`NSUserDefaults` CA92.1, `NSFileTimestamp` C617.1) with no tracking
  domains and no collected data types.
- **App sandbox enabled**: Hardened runtime + sandbox + capability entitlements
  for network, file picker, photos, scripting (Music.app), audio input,
  application groups.
- **ViewModel layer** (#166): New `ViewModels/` directory with reference
  implementation (`AIGenerateViewModel`) and pattern guide. AI generation
  pipeline lifted out of the view, dependency-injectable for testing.
- **Window chrome** (#190 → #195): Settings migrated from `Settings { }` to
  `WindowGroup(id: "settings")` with manual `⌘,` wiring so `.hiddenTitleBar`
  actually applies; compact wordmark inhabits the title-bar zone; macOS focus
  rings on dark glass are suppressed via `.focusEffectDisabled()` (macOS 14+).

### Bug Fixes
- **Appearance toggle now actually takes effect** (#200): `ThemeManager` was
  setting `NSApp.appearance` correctly but five places forced `.dark` /
  `.darkAqua` overrides, masking the change. All five sites now defer to
  `ThemeManager.appearanceMode.{swiftUIColorScheme,nsAppearance}`. Existing
  open windows pick up the change via a new `.appAppearanceDidChange`
  notification observed by `WindowChrome`.
- **Audio Visualizer disabled** (#199): The Settings entry and menu-bar
  toggle were removed prior to release because the ScreenCaptureKit /
  microphone permission flow surfaced repeatedly with poor UX. The
  implementation files are retained for a future re-enable; an AppStorage
  migration clears the persisted `enabled` flag on upgrade.
- **Smart Tags hidden** (#204): Ollama Vision auto-tagging is opt-in and
  was hidden from the Settings sidebar for the App Store submission. The
  feature, including SSRF hardening below, remains in the codebase for
  future enablement.

### Security
- **SSRF hardening** (H1, M2): Ollama Vision endpoint is now hard-restricted
  to loopback (`localhost`, `127.0.0.1`, `::1`) or `*.local` mDNS hosts. Non-
  loopback hosts must use HTTPS. Validation runs in two places: the Settings
  text field surfaces rejections inline (Tag button disabled until the
  endpoint is valid), and `OllamaVisionTagger.tags(for:)` re-checks at request
  time as defense-in-depth.
- **Re-consent on endpoint change** (M1): Any mutation of `ollama.endpoint`
  invalidates the in-session batch authorization; users must explicitly click
  "Tag" again before the next batch ships thumbnails to the new host.
- **Window chrome guard** (M3): `cinematicWindowChrome()` now skips
  non-`.titled` windows (popovers, sheets, panels) so the modifier can't
  accidentally corrupt unrelated NSWindow chrome if misapplied.
- **Deep link `import` action** now requires HTTPS and prompts the user before
  downloading. Was an arbitrary-URL vector.
- **WKWebView in Discover** refuses JS-driven popup auto-open and rejects
  non-HTTP(S) schemes (`file://`, `javascript:`, custom).
- **URLImporter** validates HTTPS scheme + response Content-Type against a
  video MIME allowlist before importing.
- **Deep link logging** strips query parameters from the public `os.log`
  channel.

### Changed
- **MRMediaRemote gated to `#if DEBUG`** (#165): Release builds ship without
  private framework references; `DistributedNotificationCenter` (Apple Music +
  Spotify) remains the public-API fallback.
- **Centralized `os.log` logging** (#169): 93 `print` / `NSLog` calls across 34
  files replaced with a `Log` registry covering 32 categories. `.debug` entries
  are stripped from Release builds automatically.
- **WallpaperManager decomposition** (#149): 808 → 462 lines. New
  `WallpaperLibrary`, `WallpaperMetadataStore`, `WidgetSyncService` peers.
- **Notification → delegate refactor** (#170): Playback flows now use a typed
  `PlaybackDelegate` protocol; broadcast consumers (widget) still use
  notifications.
- **Centralized error surfacing** (#167): New `ErrorReporter` for non-fatal
  failures the user should see. Cache decode/encode failures in
  `WallpaperManager`, `WallpaperMetadataStore`, `CollectionManager`,
  `SpaceWallpaperManager` now log and reset corrupt blobs instead of swallowing.
  Drag-drop import + Discover WKDownload import now show alerts on failure.
- File-system paths in `WallpaperMetadataCache` logs now use `privacy(.private)`
  (L1).
- `OllamaVisionTagger.parseTags` caps results at 8 tags (L3) — bounds
  worst-case `addTag` cost against pathological model responses.
- `WallpaperMetadataCache.pruneMissing` wraps DELETE loop in a single
  `BEGIN IMMEDIATE / COMMIT` transaction (L4) — atomic cache state on crash.

### Performance
- **GrainOverlay rasterized** (P0-1): noise canvas now drawn once via
  `.drawingGroup()` and reused as a Metal-backed cache instead of redrawing
  every animation frame.
- **HomeView scroll telemetry** (P0-2): replaced the recursive
  `DispatchQueue.async` + `@State` layout-invalidation pattern with a
  `PreferenceKey` reader.
- **AmbientStage cursor** (P0-3): cursor spotlight is now an independent
  view from the drift/vignette layers, and pointer → state writes are
  throttled to 30 Hz.
- **WallpaperManager O(1) index** (P1-4, KRITIK-1): `indexById` dictionary
  maintained alongside the array; index rebuild only fires on structural
  changes (length/order), not on subscript mutations of existing entries.
- **Debounced persistence** (P1-6): favorite/title/tag JSON writes coalesce
  into a single 250 ms-deferred encode instead of one write per click.
- **CarouselCard pointer throttle** (P1-7): same 30 Hz gate as ambient.
- **Liquid Glass control tone** (P2-8): inline controls skip the
  `.regularMaterial` blur, reducing stacked-material passes per window.
- **Hero animation** (P2-10, ORTA-1): `withAnimation(repeatForever)` replaced
  with `TimelineView` driven from elapsed-since-appear (no wall-clock jump
  on sleep/wake), and paused when the window is occluded (ORTA-2).
- **Search routing** (P3-11): libraries > 200 wallpapers route through the
  SQLite cache index instead of fuzzy in-memory scan.
- **Bulk import** (P3-12, YUKSEK-1, KRITIK-2): `importVideos` now maintains
  a max-4 in-flight producer-consumer window (not a serial batch), and each
  call's critical section (duplicate-check + file move + array append) runs
  through a serial `ImportGate` actor — concurrent identical drops can no
  longer race past duplicate detection.
- **FFT hot-path** (#163): Pre-allocated vDSP buffers and pointer arithmetic
  eliminate ~280 allocations/sec on the visualizer path.
- **`CGWindowListCopyWindowInfo`** moved off the main thread (#168).
- **Idle CPU**: Instruments sample with the app idle measured 4.1–4.4 % CPU
  (vs. ~15–25 % before the perf sweep).

### Tests
- 86/86 unit tests pass.
- +5 covering Ollama endpoint allowlist (loopback / `*.local` / public /
  non-http) and `parseTags` cap.
- +5 covering `SlideshowGenerator.totalFrames` (YUKSEK-2): empty input,
  crossfade math, no-transition mode.
- +7 covering `WallpaperMetadataCache` SQLite roundtrip.

### Removed prior to release
- **Audio Visualizer overlay** (#129, #159, #160, #161, #162): UI entry
  points and lazy initialization removed. Implementation files retained.
- **Smart Tags (Ollama Vision)** (#116): Settings sidebar entry removed.
  Service + view + tests retained.

### Changed
- **MRMediaRemote gated to `#if DEBUG`** (#165): Release builds ship without
  private framework references; `DistributedNotificationCenter` (Apple Music +
  Spotify) remains the public-API fallback.
- **Centralized `os.log` logging** (#169): 93 `print` / `NSLog` calls across 34
  files replaced with a `Log` registry covering 32 categories. `.debug` entries
  are stripped from Release builds automatically.
- **WallpaperManager decomposition** (#149): 808 → 462 lines. New
  `WallpaperLibrary`, `WallpaperMetadataStore`, `WidgetSyncService` peers.
- **Notification → delegate refactor** (#170): Playback flows now use a typed
  `PlaybackDelegate` protocol; broadcast consumers (widget) still use
  notifications.
- **Centralized error surfacing** (#167): New `ErrorReporter` for non-fatal
  failures the user should see. Cache decode/encode failures in
  `WallpaperManager`, `WallpaperMetadataStore`, `CollectionManager`,
  `SpaceWallpaperManager` now log and reset corrupt blobs instead of swallowing.
  Drag-drop import + Discover WKDownload import now show alerts on failure.

### Performance
- **FFT hot-path** (#163): Pre-allocated vDSP buffers and pointer arithmetic
  eliminate ~280 allocations/sec on the visualizer path.
- **`CGWindowListCopyWindowInfo`** moved off the main thread (#168).
- **`NSColor → RGB`** conversion cached via `@State + .onChange` in
  `AudioVisualizerOverlayView`.

### Security
- **Deep link `import` action** now requires HTTPS and prompts the user before
  downloading. Was an arbitrary-URL vector.
- **WKWebView in Discover** refuses JS-driven popup auto-open and rejects
  non-HTTP(S) schemes (`file://`, `javascript:`, custom).
- **URLImporter** validates HTTPS scheme + response Content-Type against a
  video MIME allowlist before importing.
- **Deep link logging** strips query parameters from the public `os.log`
  channel.

### Tests
- 37 unit tests covering Wallpaper model, URL helpers, async initialization
  (#140 — landed in v1.2-track, included for completeness).

## [1.2.0] — 2026-04-08

### Added
- **Dynamic Island**: Floating pill UI at the screen top with compact/expanded
  modes, playback controls, rename, and auto-collapse. Notch-aware layout for
  MacBook Pro.
- **Wallpaper rename**: Custom display titles via `customTitle` field.
  Right-click → Rename on all screens (Home, Explore, Popular, Library).
- **Dock icon hiding**: Settings → General → "Hide Dock icon" to run as a
  menu-bar-only app.
- **Striking UI effects**: Glow cards, neon navigation tabs, glass morphism,
  shimmer, staggered entrance animations, animated gradient background.

### Fixed
- Equatable/Hashable contract violation.
- `importVideo` copying the wrong file after format conversion.
- Force-unwrap safety on `NSScreen` and array access.
- Infinite loop prevention in random wallpaper.

## [1.1.0] — 2026-03

### Added
- Netflix-style UI redesign with Home, Explore, Popular, Discover tabs.
- Discover wallpaper sources: Pixabay, Pexels, MyLiveWallpapers, DesktopHut,
  MoeWalls, MotionBGs.
- Per-Space wallpapers, Lock screen video, Wallpaper effects.
- Time-of-day auto switch, Apple Shortcuts & Siri integration.
- GIF/WebM/WebP format support, crossfade transitions, performance modes.
