# Changelog

All notable changes to Wallnetic are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.0] — Unreleased

### Added
- Playback profiles in Settings > Playback: Quality, Balanced and Battery Saver.
  With the Metal renderer they show the wallpaper at up to 60, 30 or 15 frames
  per second at normal video speed, and the menu bar names the current profile.
  A change applies at once to every display, including displays connected later,
  and never pauses, resumes or reloads playback. The AVPlayer renderer keeps the
  video's own frame rate in every profile.
- Pause After stops wallpaper motion after a chosen time and keeps the last
  frame on screen: Settings > Playback > Pause After, off by default. Set a
  default interval (presets from 15 seconds to 15 minutes, or a custom time from
  1 second to 24 hours), and give any Library wallpaper its own interval, Never
  Pause or Use Default. Each display times its own wallpaper from that video's
  first frame, and its status then reads Playback timer finished. Play, a
  wallpaper change or an automatic resume, for example after unlock, starts a
  new interval. Removing a wallpaper from the Library also removes its own
  interval.
- Replay when the desktop becomes clear, an optional Pause After setting that is
  off by default, plays a timed-out wallpaper again after app windows have
  covered and then uncovered its display; detection takes a few seconds. It
  never overrides a manual Pause, Calm Mode or a power pause, and it looks only
  at where app windows are, with no extra permission. Covering the desktop never
  pauses playback.
- The menu bar lists each display's playback status: Playing, Loading
  wallpaper…, Waiting for video, paused with its reason (for example Paused by
  you, Paused on battery, Paused for a fullscreen app or Playback timer
  finished), Wallpaper unavailable or No wallpaper selected. A display's submenu
  explains the status and any other active pause conditions, and Settings >
  Display shows the same status for each display. When a video is missing or
  cannot be played, Retry wallpaper reloads it on that display only and keeps
  any pause. Play is unavailable while a condition such as battery power, a
  fullscreen app or Calm Mode holds playback.
- Calm Mode holds wallpaper motion on the current frame. Turn it on from the
  menu bar, the Playback menu, Settings > Playback, Command–Shift–M while
  Wallnetic is active, or Shortcuts on macOS 14 or later. Turning it off resumes
  playback only when nothing else holds it, and Calm Mode turns off when
  Wallnetic quits.
- Optional thermal-aware playback (Settings > Playback > Pause wallpaper when
  the Mac gets hot, off by default) pauses the wallpaper after sustained heat,
  or at once when the Mac is critically hot, and releases its hold after a
  minute of cooling. Manual pauses, power restrictions and finished Pause After
  timers stay in effect.
- The welcome tour's first page can apply a wallpaper right away: Try a sample
  uses a short video included with the app, and Import my video… uses one of
  your own. Both apply to all displays by default; choosing one display switches
  to Different per display and leaves the other displays as they were. The
  sample works offline and becomes an ordinary Library copy you can delete, and
  imported videos are copied without changing the originals. Manual pause and
  power settings still apply. Show welcome tour and sample in Settings > General
  opens the tour again without resetting preferences.
- Settings > Storage shows how much space Library videos, generated still images
  for the system wallpaper and caches use. Library videos can be sorted by size
  or name, selected one by one or all at once, and removed after a confirmation
  that shows how many files and how much space they take. Clear unused caches
  removes only widget thumbnails that nothing uses. Only Wallnetic's own Library
  copies are listed, original files are never touched, and anything that could
  not be removed is listed with the reason.
- Create Optimized Copy… in the Library and Home context menus makes a separate,
  silent copy of a video, with resolution and frame rate capped by the Compact,
  Balanced or HEVC preset. HEVC is offered only on Macs that support it.
  Playback speed and length stay the same, and the original is never changed.
  Nothing is converted until Create copy, and a cancelled or failed conversion
  adds nothing to Library. You can preview both videos and compare their file
  sizes before choosing one; a copy can be larger than the original, and the
  result says so. If checking the video fails, Check video again tries once
  more. HDR, wide-color, transparent and anamorphic videos are not supported.
  The copy is named after the original, and Use Original Video in its context
  menu switches back.
- Optional wallpaper packs in Discover > Browse Packs, starting with Soft
  Motion: two original, silent, MIT-licensed animations. Previews, sizes,
  credits and the license show before anything is downloaded. Downloads come
  from Wallnetic's GitHub repository only when you choose Download Pack, can be
  cancelled and retried, are checked before they are added to Library, and never
  change the current wallpaper. Remove Copies deletes only pack files that are
  unchanged. Refresh Catalog looks for new packs only when you choose it.
- Daily wallpaper schedules on a timeline in Settings > Schedule, replacing the
  four fixed time-of-day slots. Turn on Daily wallpaper schedule and add your
  own ranges. Drag a range to move it, drag its handles to resize it in
  five-minute steps, or choose Edit to type exact times and pick a wallpaper.
  Ranges can cross midnight but cannot overlap. In a gap, or when a range's
  wallpaper is missing, the current wallpaper stays. The schedule follows the
  Mac's local time and time zone, and after sleep or a relaunch it switches to
  the range for the current time without replaying missed changes.
- Playlists can give each wallpaper its own duration, from one second to 24
  hours: turn on Set a duration for each item in Settings > Playlist. The list
  starts as a copy of the current source at its interval, and you can add,
  reorder, edit or remove items. Missing items are marked and skipped. Turning
  the option off returns to Whole Library, Favorites or Collection rotation, and
  both setups are kept.
- Trim…, in the Library and Home context menus, loops a chosen part of a video
  without changing or re-encoding the original. Start and End move frame by
  frame with the keyboard and VoiceOver, a loop is at least one second long,
  both renderers loop only the chosen part, and an edit never resumes a paused
  wallpaper. If the range no longer fits the file, the card shows Trim not
  applied and the full video plays. With Sync video frame to system wallpaper
  on, the system wallpaper still comes from inside the range, and optimized
  copies keep the range when it fits the copy.
- An optional clock, with an optional date, on each display's live wallpaper:
  Settings > Effects > Desktop Clock, off by default, with a choice of position
  and size. It sits below desktop icons, is in English with the region's date
  and time format and the 12/24-hour setting (limits in docs/DESKTOP_CLOCK.md),
  and updates at each minute change, also over a paused wallpaper. It hides
  while displays sleep, the session is locked or a screen saver runs, and it
  never changes playback. Wallpaper effects do not alter it, and the lock screen
  does not show it.

### Changed
- Balanced is the default playback profile, so with the Metal renderer, which is
  the default, videos recorded above 30 frames per second play less smoothly
  than in 1.4.2 until you choose Quality in Settings > Playback.
- A manual Pause now lasts until you press Play: choosing a wallpaper, Next
  Wallpaper, a playlist or a schedule no longer resumes playback. With the Metal
  renderer, a wallpaper chosen while paused appears when you press Play.
- Any change that puts one wallpaper on all displays now also sets Settings >
  Display > Wallpaper Mode to Same on all displays, so that wallpaper stays on
  every display after a relaunch and on displays connected later. This covers
  Set as Wallpaper, Next Wallpaper, favorites in the menu bar and widgets,
  Shortcuts, schedules, playlists and saved Space choices. Per-display choices
  are kept and come back when you choose Different per display again.
- Choosing a wallpaper yourself, for all displays or for one, including Next
  Wallpaper and applying a saved Space choice, or changing Wallpaper Mode, now
  holds an active daily schedule or playlist for 30 minutes. After that, the
  schedule returns to the current range's wallpaper and a playlist to the item
  that is due. In 1.4.2 the schedule kept a manual choice until the next time
  slot, and a playlist replaced it at its next interval. The hold survives a
  relaunch, and Resume schedule now or Resume playlist now ends it early.
- Playlists, in every mode, now keep time across pauses, sleep and relaunches.
  After a relaunch the playlist continues with the wallpaper that is due instead
  of restarting its interval, and editing the playlist starts a new cycle.
  Shuffle plays each wallpaper once per cycle instead of picking at random each
  time, and the menu bar item Shuffle Wallpapers is now Start Playlist or Stop
  Playlist.
- Upgrading keeps your time-of-day schedule: the four slots become ranges named
  Morning, Afternoon, Evening and Night with the same start times and
  wallpapers, and a schedule that was on stays on. If the saved start times were
  invalid or out of order, the default times (06:00, 12:00, 17:00 and 21:00) are
  used, the wallpapers are kept, and Settings > Schedule shows a notice.
  Playlist settings carry over unchanged.
- Settings > Spaces now keeps a list of saved wallpaper choices, and its toggle,
  formerly Different wallpaper per Space, is now Enable Space recovery. Add a
  choice with Add saved choice… or with Save for Space Recovery in a wallpaper's
  context menu; saving never changes the wallpaper. Edit renames a choice or
  picks another Library video, and a choice whose video is missing stays listed
  until you replace it. After a relaunch, a Space or display change, sleep or a
  user switch, each choice shows Needs reassignment.
- Delete in the Library and Home context menus now asks for confirmation,
  showing the file's size, and reports a file it could not remove. A deleted
  wallpaper stops on every display that shows it and leaves its collections.
  Per-display choices, saved Space choices, playlist items and schedule ranges
  that used it become unassigned. The original file it was imported from is
  kept.
- Wallpapers downloaded in Discover's browser are named after the video or link
  title or the page title, with the file name as a fallback; Library previously
  showed a generated name. The same name appears in the found-videos list,
  download progress and Library, and the Library file is saved under it, for
  example Ocean Sunset.mp4. Earlier downloads keep their names, and Rename still
  changes the title.

### Removed
- Automatic per-Space wallpaper switching was removed, because individual
  desktops cannot be reliably identified. Wallnetic no longer changes the
  wallpaper when you move to another Space, and Set for This Space is gone from
  the wallpaper menu. Wallpapers you assigned to Spaces are kept in Settings >
  Spaces as saved choices (Saved choice 1, Saved choice 2 and so on) and are
  never applied automatically. To use one, make sure Enable Space recovery is on
  in Settings > Spaces and choose Apply next to it; it sets that wallpaper on
  all displays and Spaces (docs/SPACE_RECOVERY.md).
- Settings > Notifications is gone: no feature in this version sends a
  notification, so the page only asked for a permission.
- Settings > Playlist no longer offers Collection as a source, because
  collections cannot be created in this version; a playlist that already uses
  one keeps it.
- The Transition section is gone from Settings > Effects; it only said that
  wallpaper changes are instant, which they still are.

### Fixed
- HDR videos no longer look washed out with the Metal renderer; Wallnetic
  converts them to standard dynamic range before drawing. SDR videos and the
  AVPlayer renderer are unchanged.
- Per-display wallpapers now come back after a restart and stay assigned when
  Library files are added or removed; before, every display could come back with
  the last wallpaper. Choosing one wallpaper for all displays after per-display
  choices now updates every display, and switching back to Different per display
  no longer leaves the old video on a display whose wallpaper was deleted.
  Switching to Different per display keeps what each display shows as its own
  choice, and after a restart a display without its own choice shows the last
  wallpaper. Per-display choices made in 1.4.2 are not carried over: after
  upgrading, every display starts with the last wallpaper and Wallpaper Mode
  reads Same on all displays, so choose per-display wallpapers again.
- With the Metal renderer, switching between videos of different shapes, such as
  landscape and portrait, no longer shows the previous video's last frame
  stretched while the next one loads, including while the wallpaper is paused.
- The Metal renderer no longer risks a crash when a display is disconnected, or
  Wallnetic quits, while a frame is still being drawn.
- With Sync video frame to system wallpaper on (Settings > Spaces), a display
  connected later, and each display after you switch to Different per display,
  now gets a still of the video it shows, and two displays showing the same
  video both get it. Cleaning up old stills no longer deletes one that a display
  is using.
- Settings > Display: with Different per display, each display has a Choose
  wallpaper… button, and each wallpaper in the picker is a button. Both work
  with the keyboard and VoiceOver, which names the display, the full wallpaper
  title and whether it is selected. Clicking a display's row no longer opens the
  picker.
- The welcome tour follows Reduce Motion, including changes made while it is
  open: the artwork stops moving and pages change without animation. VoiceOver
  reads each page title as a heading and the current step, shown as Step 1 of 4,
  and skips decorative artwork. The last page no longer promises per-Space
  wallpapers; it describes per-display wallpapers and saved Space choices that
  are applied manually.
- Open Wallnetic, in the menu bar and in the Dynamic Island, now brings the main
  window forward, restores it if it was minimized, or opens it again if it was
  closed. Before, it could bring a different window, such as a panel, to the
  front instead.
- Widgets show the time in the Mac's 12- or 24-hour setting instead of always
  24-hour, and dates in English with the region's formats. Their minute now
  changes with the menu-bar clock instead of up to a minute later, and a long
  12-hour time shrinks to stay on one line.
- Corrected public descriptions: ordinary windows covering the desktop do not
  pause playback, wallpaper changes are instant, saved Space choices are not
  applied automatically, and the audio visualizer, disabled since 1.3.1, no
  longer appears as a feature. The privacy policy now covers Create from Photos
  and lists every permission Wallnetic can request.

### Not in this release
- a standalone screen saver is in development and is not distributed. Neither
  the App Store nor the DMG release includes or installs it
  (docs/STANDALONE_SCREEN_SAVER.md).

## [1.4.2] — 2026-09-24

### Fixed
- More reliable wallpaper loading, switching and looping, with aspect-fill
  playback that preserves video proportions. Ordinary foreground windows no
  longer repeatedly pause and restart the wallpaper decoder.
- Playback callbacks and pending loads now respect pause, stop and replacement;
  Metal frames retain their Core Video backing until GPU work completes.
- User-requested pauses remain paused across power and session events, while
  active playback no longer blocks normal idle system sleep.
- Main and Settings use native title bars to address missing window controls
  reported on macOS 26.6.2. Reporter confirmation remains pending in #237.
- First-launch onboarding uses fixed content sizing and saves completion only
  after Skip or Enter Wallnetic, rather than immediately on presentation.
- Library imports, gallery previews, search/navigation and Settings interactions
  include the reliability and accessibility fixes from #236, #239 and #240.
- Duplicate deep-link query names and invalid MLW block lengths are rejected
  without terminating the app. ZIP extraction rejects entries declaring more
  than 512 MiB of expanded data before allocating their output buffer.

### Changed
- Wallpaper changes are currently instant; inactive transition controls have
  been replaced with an explanation of the supported behavior.

## [1.4.1] — 2026-08-08

Wallnetic decoded the wallpaper at full rate in three situations where nothing
was visible to the user. All three now stop, and each pause was built so it can
never strand the wallpaper in a frozen state.

### Added
- **Pause while the desktop is covered**: each display's wallpaper window now
  watches its own occlusion state and suspends that display's decoder while it
  is fully covered — a maximized browser, a fullscreen game, any full-screen
  window. There was no occlusion handling anywhere in the app before this, so
  this cost was paid continuously. Debounced by 500 ms because macOS delivers a
  burst of alternating notifications across a single transition, and kept
  separate from the play/pause state so the menu bar, widget and resume paths
  still reflect what the user asked for.
- **Pause on screen lock and fast user switching**: video previously decoded at
  full rate behind the login window, and indefinitely while another user was
  switched in — nothing else fires in that state, because the other user keeps
  the display awake.

### Fixed
- **Screen-saver pausing never worked**: the observers were registered on the
  local notification center for what are cross-process notification names, so
  they could never fire and the screen-saver branch of the pause logic was
  unreachable. Moved to `DistributedNotificationCenter` with immediate
  delivery — the default coalescing behaviour would have dropped them anyway,
  since the app is always inactive exactly when a screen saver starts.
- **Watchdog no longer fights the new pauses**: a suspended renderer's clock is
  frozen deliberately, which the playback watchdog would have read as a stall
  and "recovered" by restarting the decode behind the cover permanently. The
  watchdog now re-derives occlusion each tick and skips suspended displays —
  which doubles as a resync, so a dropped notification can strand a display for
  at most one tick.
- **Lock/unlock can no longer freeze the wallpaper**: state is re-derived from
  the window server on every wake, unlock and screen-saver-stop rather than
  trusting notifications to arrive in pairs. A single missed unlock would
  otherwise have left the wallpaper paused forever, since the watchdog stands
  down while paused.
- **Widget playback state** now stays in sync on the power pause/resume path.
  This was skippable while power pauses were rare; screen-lock pausing makes it
  the common case.
- **Removed an inaccurate performance claim**: the hero banner's
  "paused when the window is occluded" gate was unreachable — the flag only
  clears during teardown. The code comment and the corresponding 1.3.1
  changelog line have been corrected. Real gating needs the hosting window's
  occlusion state plus a paused-duration offset, and is tracked for a future
  release.

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

## [1.3.1] — 2026-05-30

> Hardening release. /code-review xhigh-effort tarama 15 bulgu yakaladı; 4 PR
> (security/privacy → crash → functional → correctness) ile hepsi kapatıldı.
> Ayrıca #206'da bildirilen wake/unlock crash'i kök nedeniyle düzeltildi
> (NSPanel over-release) + wake/power path main-thread hardening.
> Audio Visualizer entitlement'i tamamen kaldırıldı (UI zaten v1.3.0'da
> soft-remove edilmişti). Build 8.

### Release
- **v1.3.1 (build 8) submitted to App Store Review — 2026-06-05.**

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
  on sleep/wake).
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
