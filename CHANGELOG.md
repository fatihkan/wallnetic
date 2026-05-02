# Changelog

All notable changes to Wallnetic are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] — 2026-05-02

### Added
- **Audio Visualizer overlay** (#129): Desktop overlay showing a 64-column FFT spectrum.
  Center-out horizontal burst with an accent-to-white color gradient; captures
  microphone or system audio via ScreenCaptureKit.
- **Audio Visualizer customization** (#159, #160, #161, #162): Sensitivity slider
  (0.3x – 3.0x), three render styles (Bars / Waveform / Dots), six on-screen
  positions (4 corners + 2 centers), three size presets (S / M / L).
- **Battery prompt with override toggle** (#172): When the Mac switches to battery
  (or launches on battery), users see a prompt offering to keep the live wallpaper
  running. New `Playback → Always play on battery` Settings toggle makes the
  choice permanent; `Reset battery prompt` brings the dialog back.
- **Global hotkeys**: `⌘⇧→` next, `⌘⇧←` previous, `⌘⇧P` play/pause, `⌘⇧R` random.
- **Photos slideshow generator** (#137): Create wallpapers from your Apple Photos
  library. Multi-select grid, Ken Burns pan/zoom, crossfade transitions, three
  resolution presets (1080p / 1440p / 4K), 50-photo cap.
- **Privacy Manifest** (#164): `PrivacyInfo.xcprivacy` declares required-reason
  APIs (`NSUserDefaults` CA92.1, `NSFileTimestamp` C617.1) with no tracking
  domains and no collected data types.
- **App sandbox enabled**: Hardened runtime + sandbox + capability entitlements
  for network, file picker, photos, scripting (Music.app), audio input,
  application groups.
- **ViewModel layer** (#166): New `ViewModels/` directory with reference
  implementation (`AIGenerateViewModel`) and pattern guide. AI generation
  pipeline lifted out of the view, dependency-injectable for testing.

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
