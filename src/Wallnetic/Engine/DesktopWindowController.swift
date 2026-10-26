import Cocoa
import AVFoundation
import QuartzCore
import Combine

/// Protocol for video renderers (supports both AVFoundation and Metal-based renderers)
protocol WallpaperRenderer: AnyObject {
    var playbackMonitor: RendererPlaybackMonitor { get }
    var rendererView: NSView { get }
    /// Loads a video and loops only `trim`'s range while it still applies to
    /// the file; nil, or a range that cannot apply, plays the full video.
    func loadVideo(url: URL, trim: PlaybackTrim?)
    /// Reloads the current video with an edited loop range without changing
    /// play/pause intent. A paused renderer applies it when it next resumes.
    func applyTrim(_ trim: PlaybackTrim?)
    func play()
    func pause()
    func stop()
    func applyPerformanceMode(_ mode: PerformanceManager.PerformanceMode)
    /// Current playback position in seconds, or `nil` when no player is loaded.
    /// The watchdog samples this to detect a frozen player (time not advancing).
    var currentPlaybackTime: TimeInterval? { get }
    /// Nudge a stalled or rate-drifted renderer without seeking.
    /// Seeking rolls back to the previous keyframe (a few-frame rewind).
    func recoverPlayback()
    /// Current `AVPlayer.rate`, or 0 when no player is loaded.
    var currentPlaybackRate: Float { get }
    /// True once at least one frame has been presented. The desktop overlay
    /// must stay hidden until this is set, or it covers the real wallpaper
    /// with an opaque black window.
    var hasPresentedFrame: Bool { get }
    var onBecameReady: (() -> Void)? { get set }
    /// Layer that actually shows video pixels — CIFilter effects must land
    /// here, not on a container that AppKit uses for layout.
    var filterLayer: CALayer? { get }
    /// Keep decode/present running while the app is inactive or the desktop
    /// window is occluded by a windowed (non-fullscreen) app. A restart when
    /// that app leaves the foreground is the remaining hitch.
    func maintainPlayback()
}

extension WallpaperRenderer {
    /// The full video, for callers without a stored loop range.
    func loadVideo(url: URL) {
        loadVideo(url: url, trim: nil)
    }
}

// Conform VideoRenderer to the protocol
extension VideoRenderer: WallpaperRenderer {
    var rendererView: NSView { return view }
}

// Conform MetalVideoRenderer to the protocol
extension MetalVideoRenderer: WallpaperRenderer {
    var rendererView: NSView { return metalView }
}

/// Controls the desktop-level window that displays live wallpapers behind desktop icons
/// Optimized for minimal resource usage
class DesktopWindowController {
    // Keyed by CGDirectDisplayID, not the NSScreen object. NSScreen identity
    // is recreated on display reconfiguration (sleep/wake, hot-plug,
    // resolution change), which left stale object keys here and made
    // per-screen lookups miss — the reported "main display doesn't update in
    // different mode" bug. displayID is stable across those events.
    private var desktopWindows: [CGDirectDisplayID: NSWindow] = [:]
    private var renderers: [CGDirectDisplayID: WallpaperRenderer] = [:]
    private var performanceBindings: [CGDirectDisplayID: AnyCancellable] = [:]
    private var effectOverlays: [CGDirectDisplayID: NSView] = [:]
    private let durationPlayback = PauseAfterPlayback(canPlay: { !PowerManager.shared.shouldBePaused })
    private var isPlaying: Bool { durationPlayback.isRequested }
    private var durationTimer: Timer?
    private var durationSettingsObserver: AnyCancellable?
    private var calmSettingsObserver: AnyCancellable?
    private let desktopClearMonitor = DesktopClearMonitor()
    private var reportedPlaying: Bool?
    private var reportedDurationPause: Bool?
    var onPlaybackStateChanged: ((Bool, Bool) -> Void)?
    var onDisplayStatusesChanged: (([DisplayPlaybackStatus]) -> Void)? {
        didSet {
            reportedStatuses = []
            refreshPlaybackStatuses()
        }
    }
    private var reportedStatuses: [DisplayPlaybackStatus] = []
    private var statusObservers: [AnyCancellable] = []
    /// Last URL applied to *all* screens (uniform mode). Used to restore
    /// new screens on hot-plug and to skip redundant uniform reapplies.
    private var currentWallpaperURL: URL?
    /// Per-display URL state. Lets the per-screen path skip a redundant
    /// reload on the same display while still allowing two displays to share
    /// the same source URL in "different per display" mode.
    private var screenWallpaperURLs: [CGDirectDisplayID: URL] = [:]
    private var useMetalRenderer: Bool
    /// Keeps App Nap from throttling decode while a foreground app is active.
    private var playbackActivity: NSObjectProtocol?
    private let trimStore: PlaybackTrimStore
    private var trimObserver: AnyCancellable?

    init(trimStore: PlaybackTrimStore = .shared) {
        self.useMetalRenderer = WallpaperManager.shared.useMetalRenderer
        self.trimStore = trimStore
        setupDesktopWindows()
        setupEffectsObserver()
        // `@Published` emits before it stores, so use the emitted ranges.
        trimObserver = trimStore.$trims.dropFirst().sink { [weak self] trims in
            self?.applyTrimEdits(trims)
        }
        durationPlayback.onChange = { [weak self] in self?.refreshPlaybackLifecycle() }
        calmSettingsObserver = CalmPlaybackSettings.shared.$state
            .map(\.holds).removeDuplicates().sink { [weak self] holds in
                self?.durationPlayback.setHolds(holds)
            }
        durationSettingsObserver = PauseAfterSettings.shared.$preferences.sink { [weak self] preferences in
            self?.durationPlayback.updatePreferences(preferences)
            self?.refreshPlaybackLifecycle(preferences: preferences)
        }
        desktopClearMonitor.onDesktopCleared = { [weak self] id in
            self?.durationPlayback.replayExpiredDisplay(id)
        }
        for name in [Notification.Name.playbackRestrictionsDidChange, UserDefaults.didChangeNotification] {
            statusObservers.append(NotificationCenter.default.publisher(for: name)
                .receive(on: RunLoop.main).sink { [weak self] _ in self?.refreshPlaybackStatuses() })
        }
    }

    private func setupEffectsObserver() {
        NotificationCenter.default.addObserver(
            forName: .wallpaperEffectsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyEffects()
        }
    }

    // MARK: - Window Setup

    /// Creates desktop windows for all connected screens
    func setupDesktopWindows() {
        for screen in NSScreen.screens {
            createDesktopWindow(for: screen)
        }
    }

    /// Creates a single desktop window for a specific screen
    private func createDesktopWindow(for screen: NSScreen) {
        // A display with no NSScreenNumber can't be tracked stably; skipping
        // it is safer than keying by an unstable fallback.
        guard let displayID = screen.displayID else {
            Log.window.error("Skipping desktop window: screen has no displayID (\(screen.localizedName, privacy: .public))")
            return
        }

        // Defer creation for performance. isReleasedWhenClosed=false is baked
        // into the factory so ARC alone owns the window. [#206]
        // Start clear + fully transparent: an opaque black window ordered
        // front before the first decoded frame *is* the black-desktop bug.
        let window = OverlayWindowFactory.makeBackgroundWindow(
            contentRect: screen.frame,
            opaque: false,
            backgroundColor: .clear
        )

        // Position window at desktop level (behind icons, above actual desktop)
        let desktopIconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        window.level = NSWindow.Level(rawValue: desktopIconLevel - 1)

        // Window behavior - optimized for background operation
        window.collectionBehavior = [
            .canJoinAllSpaces,      // Show on all spaces
            .stationary,             // Don't move with space switches
            .ignoresCycle,           // Don't include in Cmd+Tab
            .fullScreenNone          // Never go fullscreen
        ]

        // Visual properties - optimized for performance (opaque is faster)
        window.ignoresMouseEvents = true
        window.acceptsMouseMovedEvents = false

        // Disable window animations
        window.animationBehavior = .none

        // Prevent window from being closed/minimized
        window.styleMask.remove(.closable)
        window.styleMask.remove(.miniaturizable)

        // Create and attach video renderer (Metal or AVFoundation based)
        let renderer: WallpaperRenderer
        if useMetalRenderer && MetalVideoRenderer.isSupported {
            renderer = MetalVideoRenderer()
        } else {
            renderer = VideoRenderer()
        }

        renderer.rendererView.frame = NSRect(origin: .zero, size: screen.frame.size)
        renderer.rendererView.autoresizingMask = [.width, .height]
        renderer.rendererView.wantsLayer = true
        window.contentView = renderer.rendererView
        renderer.onBecameReady = { [weak self] in
            self?.revealDesktopWindow(for: displayID)
        }
        // Readiness can change while an old frame remains visible. Start/stop
        // the duration timer on those events instead of polling a pending load.
        renderer.playbackMonitor.onChange = { [weak self] in self?.refreshPlaybackLifecycle() }

        // Create effect overlay view
        let effectOverlay = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        effectOverlay.autoresizingMask = [.width, .height]
        effectOverlay.wantsLayer = true
        effectOverlay.layer?.zPosition = 100
        renderer.rendererView.addSubview(effectOverlay)
        effectOverlays[displayID] = effectOverlay

        // Store references
        desktopWindows[displayID] = window
        renderers[displayID] = renderer
        performanceBindings[displayID] = PerformanceManager.shared.bind(to: renderer)

        // Apply current effects
        applyEffectsToOverlay(effectOverlay)

        // Park the window off the desktop until a frame exists. orderFront
        // of an empty opaque surface is a black screen; alpha=0 keeps it
        // in the window list (for later reveal) without covering anything.
        window.alphaValue = 0
        window.orderFront(nil)

        let rendererName = useMetalRenderer ? "Metal" : "AVFoundation"
        Log.window.debug("Created window for: \(screen.localizedName, privacy: .public) using \(rendererName, privacy: .public) renderer")
    }

    /// Makes the overlay visible only after the renderer has a frame.
    private func revealDesktopWindow(for displayID: CGDirectDisplayID) {
        guard let window = desktopWindows[displayID],
              let renderer = renderers[displayID],
              WallpaperVisibilityPolicy.shouldShowOverlay(hasPresentedFrame: renderer.hasPresentedFrame)
        else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        window.alphaValue = 1
        window.isOpaque = true
        window.backgroundColor = .black
        window.orderFront(nil)
        CATransaction.commit()
        Log.window.debug("Revealed desktop window for display \(displayID, privacy: .public)")
    }

    // MARK: - Playback Control

    func wallpaperURL(on displayID: UInt32) -> URL? { screenWallpaperURLs[displayID] }

    /// Sets the wallpaper video on one screen, or on every screen when
    /// `screen` is nil. The change is instant.
    func setWallpaper(url: URL, for screen: NSScreen? = nil, forceReload: Bool = false) {
        // Resolve the optional target screen to a stable display id up front.
        // A target screen with no displayID can't be addressed — bail rather
        // than silently apply to the wrong display.
        let targetID: CGDirectDisplayID?
        if let screen {
            guard let id = screen.displayID else {
                Log.window.error("setWallpaper: target screen has no displayID")
                return
            }
            targetID = id
        } else {
            targetID = nil
        }

        // Guard per scope: uniform-mode (screen=nil) skips redundant
        // reapplies only when the URL hasn't changed at all; per-screen
        // mode keys the skip check on the target display so two displays
        // can share the same source URL without one being silently dropped.
        if let targetID {
            guard forceReload || screenWallpaperURLs[targetID] != url else { return }
            screenWallpaperURLs[targetID] = url
        } else {
            guard forceReload || currentWallpaperURL != url ||
                    renderers.keys.contains(where: { screenWallpaperURLs[$0] != url }) else { return }
            currentWallpaperURL = url
            // Uniform reapply: reset per-display state so hot-plug and
            // mode transitions see a consistent picture.
            for id in desktopWindows.keys {
                screenWallpaperURLs[id] = url
            }
        }

        let displayIDs = targetID.map { [$0] } ?? Array(desktopWindows.keys)

        for s in displayIDs {
            // Window presence gates the apply; the renderer does the work.
            guard desktopWindows[s] != nil,
                  let renderer = renderers[s] else { continue }

            // Do not put CATransition on the renderer view: its backing layer
            // is the AVPlayerLayer, and a transition there animates every
            // frame (or every looper item swap) as a visible twitch.
            // The renderer keeps the previous player until the next item is
            // ready, which is the hitch-free swap.
            renderer.loadVideo(url: url, trim: trimStore.trim(for: url))
            durationPlayback.setWallpaper(url, renderer: renderer, on: s,
                                          preferences: PauseAfterSettings.shared.preferences)
        }
    }

    /// A loop-range edit reloads only the displays showing that video,
    /// through the renderer's own reload; the others ignore an unchanged
    /// range. Not `setWallpaper`: it replaces the display's Pause After entry,
    /// which would resume a pause and restart its interval.
    private func applyTrimEdits(_ trims: [String: PlaybackTrim]) {
        for (id, url) in screenWallpaperURLs {
            renderers[id]?.applyTrim(PlaybackTrimStore.trim(for: url, in: trims))
        }
    }

    /// Starts playback on all screens
    func play(explicit: Bool = false) {
        durationPlayback.play(explicit: explicit)
    }

    /// Pauses playback on all screens
    func pause(manual: Bool = false) {
        durationPlayback.pause(manual: manual)
    }

    private func refreshPlaybackLifecycle(preferences: PauseAfterSettings.Preferences? = nil) {
        defer { refreshPlaybackStatuses() }
        if durationPlayback.hasActivePlayback {
            beginPlaybackActivity()
            startWatchdog()
        } else {
            stopWatchdog()
            endPlaybackActivity()
        }
        if durationPlayback.needsTimer {
            if durationTimer == nil {
                let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                    self?.durationPlayback.tick()
                }
                timer.tolerance = 0.05
                RunLoop.main.add(timer, forMode: .common)
                durationTimer = timer
            }
        } else {
            durationTimer?.invalidate()
            durationTimer = nil
        }
        let preferences = preferences ?? PauseAfterSettings.shared.preferences
        desktopClearMonitor.setEnabled(isPlaying && durationPlayback.holds.isEmpty && durationPlayback.hasTimedWallpapers && preferences.replayWhenDesktopClears)
        let playing = durationPlayback.hasActivePlayback
        let held = durationPlayback.isPausedAfterDuration
        if reportedPlaying != playing || reportedDurationPause != held {
            reportedPlaying = playing
            reportedDurationPause = held
            onPlaybackStateChanged?(playing, held)
        }
    }

    func refreshPlaybackStatuses() {
        let restrictions = PowerManager.shared.pauseReasons
        let statuses = NSScreen.screens.compactMap { screen -> DisplayPlaybackStatus? in
            guard let id = screen.displayID, let renderer = renderers[id] else { return nil }
            var reasons = restrictions
            reasons.append(contentsOf: durationPlayback.holds.map(\.pauseReason))
            if durationPlayback.isManuallyPaused { reasons.append(.manual) }
            if durationPlayback.isExpired(on: id) { reasons.append(.timer) }
            return DisplayPlaybackStatus(id: id, displayName: screen.localizedName,
                hasWallpaper: screenWallpaperURLs[id] != nil,
                renderer: renderer.playbackMonitor.state, reasons: reasons)
        }
        guard statuses != reportedStatuses else { return }
        reportedStatuses = statuses
        onDisplayStatusesChanged?(statuses)
    }

    func retryWallpaper(on displayID: UInt32) {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }),
              let url = screenWallpaperURLs[displayID],
              renderers[displayID]?.playbackMonitor.state.isFailed == true else { return }
        setWallpaper(url: url, for: screen, forceReload: true)
        // setWallpaper resumes only an already requested session. Retry must
        // also preserve a power pause whose automatic resume was disabled.
    }

    func clearWallpaper(url: URL) {
        for id in Array(screenWallpaperURLs.keys) where screenWallpaperURLs[id] == url {
            clearWallpaper(on: id)
        }
        if currentWallpaperURL == url { currentWallpaperURL = nil }
        refreshPlaybackStatuses()
    }

    func clearWallpaper(on displayID: UInt32) {
        guard screenWallpaperURLs[displayID] != nil else { return }
        renderers[displayID]?.stop()
        screenWallpaperURLs.removeValue(forKey: displayID)
        desktopWindows[displayID]?.alphaValue = 0
        durationPlayback.remove(displayID)
        if screenWallpaperURLs.isEmpty { currentWallpaperURL = nil }
        refreshPlaybackStatuses()
    }

    /// Keep decode running when we resign active. Do not `orderFront` or
    /// re-`play()` — and do not pulse this while a windowed app stays in front.
    func maintainPlayback() {
        guard isPlaying,
              WallpaperPlaybackPolicy.shouldKeepPresentingWhileInactive(intendedToPlay: true)
        else { return }
        for (id, renderer) in renderers where durationPlayback.shouldPlay(on: id) {
            renderer.maintainPlayback()
        }
    }

    private func beginPlaybackActivity() {
        guard playbackActivity == nil else { return }
        playbackActivity = ProcessInfo.processInfo.beginActivity(
            options: [
                .userInitiatedAllowingIdleSystemSleep,
                .suddenTerminationDisabled,
                .automaticTerminationDisabled
            ],
            reason: "Live wallpaper playback"
        )
    }

    private func endPlaybackActivity() {
        if let playbackActivity {
            ProcessInfo.processInfo.endActivity(playbackActivity)
            self.playbackActivity = nil
        }
    }

    var isCurrentlyPlaying: Bool {
        return durationPlayback.hasActivePlayback
    }

    /// Power pauses must still claim an intended session held by Calm/thermal
    /// policy; otherwise their resume path would strand that session.
    var hasPlaybackResumeIntent: Bool { durationPlayback.isRequested }

    // MARK: - Playback Watchdog (v1.4 Wave 1)

    /// Samples each renderer's playback clock while playback is intended and,
    /// when the clock stops advancing, nudges the renderer back to life — the
    /// honest fix for the category's #1 complaint ("freezes, I have to reopen
    /// it"). Lives here because this controller owns the renderers and the
    /// recovery path; the stall decision is the pure ``PlaybackWatchdog``.
    private var watchdogTimer: Timer?
    private var lastPlaybackTimes: [CGDirectDisplayID: TimeInterval] = [:]
    private var frozenSampleCounts: [CGDirectDisplayID: Int] = [:]

    private func startWatchdog() {
        guard watchdogTimer == nil else { return }
        lastPlaybackTimes.removeAll()
        frozenSampleCounts.removeAll()
        let timer = Timer(timeInterval: PlaybackWatchdog.interval, repeats: true) { [weak self] _ in
            self?.checkPlaybackHealth()
        }
        // .common keeps it firing while a tracking run-loop is active (menu
        // open, live resize) rather than silently suspending.
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        lastPlaybackTimes.removeAll()
        frozenSampleCounts.removeAll()
    }

    private func checkPlaybackHealth() {
        // Don't fight an intentional pause (battery, fullscreen, sleep, screen
        // saver). When PowerManager pauses us it calls pause(), which already
        // stops the timer; this is belt-and-braces for an in-flight tick.
        let shouldBePaused = PowerManager.shared.shouldBePaused

        for (id, renderer) in renderers {
            if !durationPlayback.shouldPlay(on: id) {
                // This display is meant to be paused (a manual or power pause,
                // a Calm Mode or thermal hold, or an expired Pause After
                // timer), so its clock is frozen *on purpose*. Recovering it
                // would undo a pause another feature owns, so reset the
                // baseline instead.
                frozenSampleCounts[id] = 0
                lastPlaybackTimes[id] = renderer.currentPlaybackTime
                continue
            }

            let current = renderer.currentPlaybackTime
            let previous = lastPlaybackTimes[id]
            lastPlaybackTimes[id] = current

            let frozen = PlaybackWatchdog.isFrozen(
                previous: previous,
                current: current,
                intendedToPlay: isPlaying,
                shouldBePaused: shouldBePaused
            )

            guard frozen else {
                frozenSampleCounts[id] = 0
                if WallpaperPlaybackPolicy.shouldCorrectRate(
                    currentRate: renderer.currentPlaybackRate,
                    intendedToPlay: isPlaying
                ) {
                    renderer.recoverPlayback()
                }
                continue
            }

            let count = (frozenSampleCounts[id] ?? 0) + 1
            frozenSampleCounts[id] = count
            if count >= PlaybackWatchdog.frozenSamplesBeforeRecovery {
                Log.video.error("Playback stalled on display \(id, privacy: .public) — auto-recovering")
                renderer.recoverPlayback()
                revealDesktopWindow(for: id)
                // Reset the baseline so the post-recovery position isn't
                // mistaken for a fresh stall on the next sample.
                frozenSampleCounts[id] = 0
                lastPlaybackTimes[id] = renderer.currentPlaybackTime
            }
        }
    }

    // MARK: - Display Changes

    /// Handles display configuration changes (connect/disconnect monitors)
    func handleDisplayChange() {
        defer { refreshPlaybackStatuses() }
        let currentIDs = Set(NSScreen.screens.compactMap { $0.displayID })
        let knownIDs = Set(desktopWindows.keys)

        // Remove windows for disconnected displays
        for id in knownIDs.subtracting(currentIDs) {
            renderers[id]?.playbackMonitor.onChange = nil
            renderers[id]?.stop()
            desktopWindows[id]?.close()
            desktopWindows.removeValue(forKey: id)
            renderers.removeValue(forKey: id)
            performanceBindings.removeValue(forKey: id)
            effectOverlays.removeValue(forKey: id)
            screenWallpaperURLs.removeValue(forKey: id)
            lastPlaybackTimes.removeValue(forKey: id)
            frozenSampleCounts.removeValue(forKey: id)
            durationPlayback.remove(id)
        }

        // Add windows for newly connected displays
        for screen in NSScreen.screens {
            guard let id = screen.displayID, !knownIDs.contains(id) else { continue }
            createDesktopWindow(for: screen)

            // Load current wallpaper on the new display
            let url = WallpaperManager.shared.wallpaperMode == .different
                ? WallpaperManager.shared.wallpaper(for: screen)?.url : currentWallpaperURL
            if let url, let renderer = renderers[id] {
                screenWallpaperURLs[id] = url
                renderer.loadVideo(url: url, trim: trimStore.trim(for: url))
                durationPlayback.setWallpaper(url, renderer: renderer, on: id,
                                              preferences: PauseAfterSettings.shared.preferences)
            }
            if renderers[id]?.hasPresentedFrame == true {
                revealDesktopWindow(for: id)
            }
        }

        // Update existing windows for resolution / arrangement changes
        for screen in NSScreen.screens {
            guard let id = screen.displayID, let window = desktopWindows[id] else { continue }
            if window.frame != screen.frame {
                window.setFrame(screen.frame, display: false)
            }
        }
    }

    // MARK: - Effects

    /// Applies current effects to all screen overlays
    func applyEffects() {
        for (displayID, overlay) in effectOverlays {
            applyEffectsToOverlay(overlay)
            // Apply blur to the renderer view's layer
            if let renderer = renderers[displayID] {
                let effects = WallpaperEffectsManager.shared
                let layer = renderer.filterLayer ?? renderer.rendererView.layer

                // Build combined filter array for the video layer
                var filters: [CIFilter] = []

                // Brightness + Contrast + Saturation
                if let colorFilter = CIFilter(name: "CIColorControls") {
                    colorFilter.setValue(effects.brightness, forKey: kCIInputBrightnessKey)
                    colorFilter.setValue(effects.contrast, forKey: kCIInputContrastKey)
                    colorFilter.setValue(effects.saturation, forKey: kCIInputSaturationKey)
                    filters.append(colorFilter)
                }

                // Blur applied to the video content itself (not backgroundFilters)
                if effects.blur > 0 {
                    if let blurFilter = CIFilter(name: "CIGaussianBlur") {
                        blurFilter.setValue(effects.blur, forKey: kCIInputRadiusKey)
                        filters.append(blurFilter)
                    }
                }

                layer?.filters = effects.hasActiveEffects ? filters : []
            }
        }
    }

    /// Applies tint and vignette overlay effects
    private func applyEffectsToOverlay(_ overlay: NSView) {
        let effects = WallpaperEffectsManager.shared
        guard let layer = overlay.layer else { return }

        // Clear sublayers
        layer.sublayers?.removeAll()

        // Tint overlay
        if effects.tintEnabled {
            let tintLayer = CALayer()
            tintLayer.frame = overlay.bounds
            tintLayer.backgroundColor = effects.tintColor.withAlphaComponent(effects.tintOpacity).cgColor
            tintLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            layer.addSublayer(tintLayer)
        }

        // Vignette overlay
        if effects.vignetteEnabled {
            let vignetteLayer = CAGradientLayer()
            vignetteLayer.frame = overlay.bounds
            vignetteLayer.type = .radial
            vignetteLayer.colors = [
                NSColor.clear.cgColor,
                NSColor.black.withAlphaComponent(0.3 * effects.vignetteIntensity).cgColor,
                NSColor.black.withAlphaComponent(0.7 * effects.vignetteIntensity).cgColor
            ]
            vignetteLayer.locations = [0.3, 0.7, 1.0]
            vignetteLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
            vignetteLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
            vignetteLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            layer.addSublayer(vignetteLayer)
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        statusObservers.removeAll()
        trimObserver = nil
        onDisplayStatusesChanged = nil
        durationSettingsObserver = nil
        calmSettingsObserver = nil
        durationTimer?.invalidate()
        durationTimer = nil
        desktopClearMonitor.stop()
        durationPlayback.onChange = nil
        durationPlayback.removeAll()
        stopWatchdog()
        endPlaybackActivity()

        for renderer in renderers.values {
            renderer.playbackMonitor.onChange = nil
            renderer.stop()
        }

        for window in desktopWindows.values {
            window.close()
        }

        desktopWindows.removeAll()
        renderers.removeAll()
        performanceBindings.removeAll()
    }
}
