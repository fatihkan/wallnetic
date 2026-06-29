# Changelog

All notable changes to Wallnetic are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.4.0] — 2026-06-29

### Added
- **System wallpaper sync — lock screen & Mission Control consistency**:
  macOS renders the *system* wallpaper (not Wallnetic's video window) on the
  lock screen, in Mission Control Space previews and during Space transitions,
  so those surfaces showed an unrelated default picture. Wallnetic now
  extracts a still frame of the current video and applies it via
  `NSWorkspace.setDesktopImageURL` per screen, re-applying on Space and
  display changes. The user's original wallpaper is backed up and restored
  when the toggle is turned off (Settings → Spaces & Lock Screen).
- **In-app App Store rating prompt**: Wallnetic now asks happy users for a
  review at a genuinely positive moment — right after a deliberate wallpaper
  change — gated by app maturity (at least 3 launches and 5 successful
  applies), never on the automatic launch restore, and at most once per app
  version, on top of Apple's own annual cap. Uses the modern
  `AppStore.requestReview(in:)` API. A manual "Rate Wallnetic" link was also
  added to Settings → About.
- **Playback reliability watchdog**: addresses the category's #1 complaint
  ("the wallpaper freezes and I have to reopen the app"). While playback is
  intended and not deliberately paused, `DesktopWindowController` samples each
  display's playback clock and, if it stops advancing, nudges the renderer
  back to life (`playImmediately`). Release builds previously had no stall
  detection at all — a wedged `AVPlayer` just looked frozen. Respects
  `PowerManager` (never resumes a battery/fullscreen/sleep pause).
- **Playlist / Shuffle**: auto-rotate the desktop wallpaper on an interval
  (5 min – daily, default 30 min), shuffled or in order, from your whole
  library, just favorites, or a chosen collection. New **Settings → Playlist**
  panel and a **Shuffle Wallpapers** quick-toggle in the menu bar. Mutually
  exclusive with time-of-day switching so the two schedulers never fight.
  Automatic rotations don't count toward the rating prompt.

### Removed
- Non-functional "Show video wallpaper on lock screen" feature
  (`LockScreenManager`): a `screenSaverWindow+1` level window can never
  appear above the modern macOS lock screen (separate secure session), so
  the toggle only burned CPU on an invisible renderer (#206 Bug B). The
  honest replacement is the still-frame sync above — macOS does not allow
  third-party apps to play video on the lock screen.

### Fixed
- **Window & Settings close/minimize buttons invisible on macOS 26 (#228)**:
  the cinematic title-bar treatment set the *titled* window to
  `backgroundColor = .clear` + `isOpaque = false`, which on Tahoe removed the
  backing the traffic-light buttons composite against — so the main and
  Settings windows looked like they had no way to close or hide them, and
  users assumed the app had to stay open for the wallpaper to play. The window
  is now kept opaque (the opaque SwiftUI ambient floor already paints over it,
  so the look is unchanged) with the standard buttons explicitly visible.
  The menu-bar **Settings…** item now opens the real Settings window instead
  of the defunct system Settings scene. A one-time
  banner clarifies that closing the window does **not** stop the wallpaper
  (the desktop render is independent). "Hide Dock icon" no longer strands a
  visible window with inactive controls — the Dock icon is promoted while a
  window is open and re-hidden once the last one closes.

### Documentation
- Store media refresh: 8× branded 2560×1600 ASO screenshots + framed
  1920×1080 demo video; `apps.json` (wvw.dev) updated (#216).
- README: new hero video, branded screenshot gallery, honest-messaging
  intro (user-owned videos + free-site search — no bundled library claim),
  App Store build note for Lock Screen Video (#217).
- App Store metadata (ASO revision): title "Wallnetic: Live Wallpaper 4K",
  new subtitle/keywords, Turkish localization, revised description.

### Release
- **v1.3.1 (build 8) submitted to App Store Review — 2026-06-05.**

## [1.3.1] — 2026-05-30

> Hardening release. /code-review xhigh-effort tarama 15 bulgu yakaladı; 4 PR
> (security/privacy → crash → functional → correctness) ile hepsi kapatıldı.
> Ayrıca #206'da bildirilen wake/unlock crash'i kök nedeniyle düzeltildi
> (NSPanel over-release) + wake/power path main-thread hardening.
> Audio Visualizer entitlement'i tamamen kaldırıldı (UI zaten v1.3.0'da
> soft-remove edilmişti). Build 8.

### Security & Privacy (PR #207)
- **Spotify SSRF blocked** (`NowPlayingManager`): `DistributedNotificationCenter`
  herhangi bir lokal işlemden artwork URL inject edebiliyordu; artık https-only
  + non-loopback + non-RFC1918 host şart, file:// kapatıldı.
- **Content-Disposition substring injection** (`BrowserWebView`): `.mp4`
  substring match `video.mp4.dylib` filename'ini geçiriyordu; gerçek `filename=`
  parametresi regex ile parse ediliyor, saved file extension allowlist dışına
  çıkarsa `.zip`'e düşürülüyor.
- **PII → Keychain migration** (`AuthManager`): `userEmail`/`userId`
  UserDefaults'ta plaintext duruyordu (App Group geniş erişim, backup
  unencrypted). `KeychainManager.setSecureString` ile Keychain'e taşındı.
- **Audio Visualizer entitlement temizliği**: `com.apple.security.device.audio-input`
  + `NSMicrophoneUsageDescription` + `NSScreenCaptureUsageDescription` silindi
  (PR #199'da UI kaldırılmıştı).

### Bug Fixes — Crashes & Hangs (PR #208)
- **AIService URL force-unwrap crash**: fal.ai `requestId` URL-invalid karakter
  içeriyorsa `URL(string:)!` crash. Percent-encoded + guard + throw.
- **PhotosLibraryService continuation hang**: `requestFullImage` degraded-only
  delivery sonrasında resume çağırmıyordu; NSLock-backed `ContinuationResumeFlag`
  ile exactly-once resume.
- **WallpaperManager extractMissingColors index race**: id-tuple snapshot +
  re-resolve via `firstIndex(where: id==)`.

### Bug Fixes — Functional Regressions (PR #209)
- **NSAppleScript main thread** (`NowPlayingManager`): main thread'e taşındı.
- **Per-screen URL equality guard** (`DesktopWindowController`): per-screen
  modda aynı wallpaper iki ekrana atandığında ikinci ekran skip oluyordu;
  `screenWallpaperURLs` dict ile scope-aware skip.
- **Per-screen currentWallpaper sync** (`WallpaperManager`): per-screen modda
  `currentWallpaper` güncellenmiyordu; Dynamic Island/accent/widget stale
  kalıyordu. Active screen tespitiyle uniform pipeline tetikleniyor.
- **Signature-keyed Space assignments**: index-based + unstable window-ID
  signatures relaunch sonrası wallpaper'ları yanlış Space'e bağlıyordu;
  artık signature-keyed (eski stored index'ler harmless ignore).

### Bug Fixes — Correctness (PR #210)
- **DownloadManager data race**: tasks/completionHandlers dict'leri delegate
  queue ve main queue'dan eşzamanlı mutate ediliyordu; tüm erişim
  `stateQueue: DispatchQueue` üzerinden serialize.
- **AudioVisualizerManager stop/start race**: `isRunning = false` artık
  synchronous (önceden `DispatchQueue.main.async`'e erteleniyordu, hızlı
  toggle visualizer'ı dead state'te bırakıyordu).
- **OllamaTaggingService objectWillChange**: `@AppStorageKeyed` setter'ları
  `willSet { objectWillChange.send() }` ile SwiftUI re-render fire ediyor.

### Bug Fixes — Wake / Unlock Stability (PR #212, #211)
- **Unlock crash — EXC_BAD_ACCESS (#206)**: programatik NSPanel/NSWindow'lar
  `isReleasedWhenClosed`'ı default `true` bırakmıştı; ARC strong ref + `close()`
  çift-release demek. Bir panel `animator().setFrame` transform animasyonu uçarken
  kapanınca (wake'te `screensChanged` paneli kapatıyordu) freed panel
  `_NSWindowTransformAnimation` dealloc'ında over-release ediliyordu (CA flush,
  main-thread). 5 controller'da `isReleasedWhenClosed = false` (DynamicIsland,
  NowPlaying, DesktopOverlay, AudioVisualizer, LockScreen).
- **Power-callback main-thread guard** (`PowerManager`): `NSProcessInfoPowerStateDidChange`
  (Low Power Mode) main-thread garantili değil; playback callback'leri AppKit/AVKit'e
  dokunduğundan `runOnMain` ile main'e alındı (sleep/wake yolları zaten main →
  senkron, timing değişmedi). + 3 non-failable AV force-unwrap temizliği.

### Refactor — Window Layer & Deep Links (PR #214)
- **OverlayWindowFactory**: tüm programatik pencere/panel oluşturma tek bir
  factory'ye taşındı (`makeOverlayPanel` / `makeBackgroundWindow`), `isReleasedWhenClosed
  = false` merkezi olarak bake edildi. 6 controller migrate edildi (Desktop,
  DynamicIsland, NowPlaying, DesktopOverlay, AudioVisualizer, LockScreen) → 0 ham
  `NSPanel(`/`NSWindow(` constructor kaldı. #206 over-release bug-class'ı kökten önlenir.
- **Deep-link konsolidasyonu**: `AppDelegate.application(open:)` artık tüm `wallnetic://`
  URL'lerini tek giriş noktasından (`DeepLinkHandler`) geçiriyor (scheme doğrulama,
  routing, HTTPS-only + onay diyaloglu `import`). Paralel `WallpaperManager.handleWidgetURL`
  kaldırıldı; `open` host case eklendi.
- **Perf**: `DesktopOverlayView` DateFormatter'ları `static let`'e taşındı (clock
  render'ında yeniden tahsis yok).
- **Secret hygiene**: `SupabaseClient` — `supabaseAnonKey` yalnızca public anon key
  olmalı (asla `service_role`; App Group container okunabilir) notu eklendi.

### Documentation (PR #213)
- CHANGELOG `[1.3.1]` bölümü wake/unlock crash çalışmasını (#211/#212) kapsayacak
  şekilde güncellendi.

### Removed
- `com.apple.security.device.audio-input` entitlement
- `NSMicrophoneUsageDescription`, `NSScreenCaptureUsageDescription` (Info.plist + project.yml)

### Breaking Change
- Space wallpaper assignment storage formatı index→signature olarak değişti.
  Pre-v1.3.1 saved data otomatik ignore — kullanıcı Space wallpaper'larını
  bir kez re-assign etmek zorunda.

### Code Review Stats
- /code-review xhigh-effort: 5 angles × 8 candidates → 1-vote verify → 15
- 3 false positives refuted: MLWDecryptor matematik (zaten doğru),
  ScreenCaptureKit availability (deployment target 13.0 zaten kapsıyor),
  ZIPReader.swift (hallüsinasyon, dosya yok).
- 4 PR sequential: #207 → #208 → #209 → #210.
- Post-review wake/unlock crash fix: #211 (power hardening) → #212 (#206 panel
  over-release) → #213 (changelog) → #214 (OverlayWindowFactory + deep-link
  consolidation, 5 review findings). 6 PR toplam, 86/86 test.
- Post-review wake/unlock crash fix: #211 (power hardening) → #212 (#206 panel over-release).

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
