import Cocoa
import AVFoundation
import QuartzCore

/// Protocol for video renderers (supports both AVFoundation and Metal-based renderers)
protocol WallpaperRenderer: AnyObject {
    var rendererView: NSView { get }
    func loadVideo(url: URL)
    func play()
    func pause()
    func stop()
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
    private var effectOverlays: [CGDirectDisplayID: NSView] = [:]
    private var isPlaying = false
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

    init() {
        self.useMetalRenderer = WallpaperManager.shared.useMetalRenderer
        setupDesktopWindows()
        setupEffectsObserver()
        setupReassertObservers()
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

    private func setupReassertObservers() {
        // Only activation-policy flips need a re-pin. Observing become-active
        // or Space changes called `orderFront` on every click / Space switch
        // and presented as a twitch in the playing wallpaper.
        reassertObservers.append(NotificationCenter.default.addObserver(
            forName: .desktopWindowsNeedReassert, object: nil, queue: .main
        ) { [weak self] _ in
            self?.scheduleReassert()
        })
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
        observeOcclusion(of: window, displayID: displayID)

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

    private var reassertDebounce: Timer?

    private func scheduleReassert() {
        reassertDebounce?.invalidate()
        reassertDebounce = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.reassertDebounce = nil
            self?.reassertDesktopWindows()
        }
    }

    /// Re-pins a desktop window only when it actually dropped (level, alpha,
    /// or ordered-out). Rewriting collectionBehavior / orderFront on an
    /// already-correct window hitches the compositor — the playback twitch.
    func reassertDesktopWindows() {
        let desktopIconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        let expectedLevel = NSWindow.Level(rawValue: desktopIconLevel - 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        for (id, window) in desktopWindows {
            let renderer = renderers[id]
            let shouldShow = renderer.map {
                WallpaperVisibilityPolicy.shouldShowOverlay(hasPresentedFrame: $0.hasPresentedFrame)
            } ?? false
            let needsReassert = WallpaperPlaybackPolicy.shouldReassertWindow(
                levelMatches: window.level == expectedLevel,
                overlayShouldShow: shouldShow,
                isOrderedIn: window.isVisible,
                alphaIsFull: window.alphaValue >= 1
            )
            guard needsReassert else { continue }

            window.collectionBehavior = [
                .canJoinAllSpaces,
                .stationary,
                .ignoresCycle,
                .fullScreenNone
            ]
            window.level = expectedLevel
            window.alphaValue = 1
            window.isOpaque = true
            window.orderFront(nil)
        }

        if isPlaying {
            for (id, renderer) in renderers where !occlusionSuspended.contains(id) {
                renderer.play()
            }
        }
    }

    // MARK: - Playback Control

    /// Sets the wallpaper video with animated transition
    func setWallpaper(url: URL, for screen: NSScreen? = nil) {
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
            guard screenWallpaperURLs[targetID] != url else { return }
            screenWallpaperURLs[targetID] = url
        } else {
            guard currentWallpaperURL != url else { return }
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
            renderer.loadVideo(url: url)
        }
    }

    /// Starts playback on all screens
    func play() {
        isPlaying = true
        beginPlaybackActivity()
        for renderer in renderers.values {
            renderer.play()
        }
        // A play() issued while a desktop is fully covered must not start a
        // decode nobody can see. Windowed apps must not pause us — only a
        // fullscreen cover is allowed to.
        for id in desktopWindows.keys {
            applyOcclusion(for: id)
        }
        startWatchdog()
    }

    /// Pauses playback on all screens
    func pause() {
        guard isPlaying else { return }

        isPlaying = false
        for renderer in renderers.values {
            renderer.pause()
        }
        occlusionSuspended.removeAll()
        stopWatchdog()
        endPlaybackActivity()
    }

    private func beginPlaybackActivity() {
        guard playbackActivity == nil else { return }
        playbackActivity = ProcessInfo.processInfo.beginActivity(
            options: [
                .userInitiatedAllowingIdleSystemSleep,
                .idleSystemSleepDisabled,
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

    /// Pauses playback (used by power management)
    func pausePlayback() {
        pause()
    }

    /// Resumes playback if it was playing before
    func resumePlayback() {
        if WallpaperManager.shared.shouldAutoResume {
            play()
        }
    }

    /// Toggles play/pause state
    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    var isCurrentlyPlaying: Bool {
        return isPlaying
    }

    // MARK: - Occlusion

    /// Displays whose renderer is paused purely because the desktop window is
    /// fully covered. Deliberately separate from `isPlaying`, which must keep
    /// meaning "the user intends the wallpaper to play" for the menu bar,
    /// widget sync and the resume paths.
    private var occlusionSuspended: Set<CGDirectDisplayID> = []
    private var occlusionObservers: [CGDirectDisplayID: NSObjectProtocol] = [:]
    private var occlusionDebounce: [CGDirectDisplayID: Timer] = [:]
    private var occlusionAgreeCounts: [CGDirectDisplayID: Int] = [:]
    private var reassertObservers: [NSObjectProtocol] = []

    /// macOS delivers a burst of alternating occlusion notifications across a
    /// single cover/uncover transition (21 within 360 ms when measured here),
    /// so state is applied only once it settles. 1.0 s plus
    /// ``WallpaperPlaybackPolicy/occlusionStableSamples`` extra agrees stops
    /// the pause/resume twitch those bursts used to cause.
    private static let occlusionDebounceInterval: TimeInterval = 1.0

    private func observeOcclusion(of window: NSWindow, displayID: CGDirectDisplayID) {
        // Scoped to this window: the process also owns overlay panels and two
        // SwiftUI WindowGroups whose occlusion is none of our business.
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleOcclusionUpdate(for: displayID)
        }
        occlusionObservers[displayID] = observer
    }

    private func scheduleOcclusionUpdate(for displayID: CGDirectDisplayID) {
        occlusionDebounce[displayID]?.invalidate()
        occlusionDebounce[displayID] = Timer.scheduledTimer(
            withTimeInterval: Self.occlusionDebounceInterval,
            repeats: false
        ) { [weak self] _ in
            self?.occlusionDebounce[displayID] = nil
            self?.applyOcclusion(for: displayID)
        }
    }

    /// Suspends or resumes one display's decoder from *live* window state.
    /// Reading the state rather than trusting a notification payload is what
    /// makes a missed notification self-correcting.
    private func applyOcclusion(for displayID: CGDirectDisplayID) {
        guard let window = desktopWindows[displayID],
              let renderer = renderers[displayID] else { return }

        // `.visible` is all-or-nothing — cleared only when the window is
        // *fully* covered — so partial overlap never pauses the wallpaper.
        // An un-revealed (alpha 0) window also reports not-visible; pausing
        // then would freeze a black overlay before the first frame.
        guard window.alphaValue >= 1 else { return }

        let visible = window.occlusionState.contains(.visible)
        // Windowed foreground apps must never pause decode. Occlusion of a
        // desktop-level window flaps around ordinary windows and is the
        // brief-pause / rate-wobble / keyframe-rollback chain.
        let fullscreenCover = false
        let wantSuspended = WallpaperVisibilityPolicy.shouldSuspendDecode(
            intendedToPlay: isPlaying,
            windowReportsVisible: visible,
            hasPresentedFrame: renderer.hasPresentedFrame,
            fullscreenAppCoversDisplay: fullscreenCover
        )
        let currentlySuspended = occlusionSuspended.contains(displayID)

        if wantSuspended == currentlySuspended {
            occlusionAgreeCounts[displayID] = 0
            return
        }

        let agrees = (occlusionAgreeCounts[displayID] ?? 0) + 1
        occlusionAgreeCounts[displayID] = agrees
        guard WallpaperPlaybackPolicy.shouldCommitOcclusionChange(
            currentlySuspended: currentlySuspended,
            wantSuspended: wantSuspended,
            consecutiveAgrees: agrees
        ) else { return }

        occlusionAgreeCounts[displayID] = 0
        if wantSuspended {
            occlusionSuspended.insert(displayID)
            renderer.pause()
            Log.window.debug("Display \(displayID, privacy: .public) fully occluded — decode suspended")
        } else {
            occlusionSuspended.remove(displayID)
            if isPlaying { renderer.play() }
            Log.window.debug("Display \(displayID, privacy: .public) visible again — decode resumed")
        }
    }

    private func removeOcclusionTracking(for displayID: CGDirectDisplayID) {
        if let observer = occlusionObservers.removeValue(forKey: displayID) {
            NotificationCenter.default.removeObserver(observer)
        }
        occlusionDebounce.removeValue(forKey: displayID)?.invalidate()
        occlusionSuspended.remove(displayID)
        occlusionAgreeCounts.removeValue(forKey: displayID)
    }

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
            // Re-derive occlusion from live state first. This doubles as a
            // resync: a dropped notification can strand a display suspended
            // for at most one watchdog tick.
            applyOcclusion(for: id)
            if occlusionSuspended.contains(id) {
                // A suspended renderer's clock is frozen *on purpose*. Letting
                // the watchdog see that would restart the decode behind the
                // cover permanently — the exact waste this pause exists to
                // avoid — so reset the baseline instead.
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
        let currentIDs = Set(NSScreen.screens.compactMap { $0.displayID })
        let knownIDs = Set(desktopWindows.keys)

        // Remove windows for disconnected displays
        for id in knownIDs.subtracting(currentIDs) {
            removeOcclusionTracking(for: id)
            renderers[id]?.stop()
            desktopWindows[id]?.close()
            desktopWindows.removeValue(forKey: id)
            renderers.removeValue(forKey: id)
            effectOverlays.removeValue(forKey: id)
            screenWallpaperURLs.removeValue(forKey: id)
            lastPlaybackTimes.removeValue(forKey: id)
            frozenSampleCounts.removeValue(forKey: id)
        }

        // Add windows for newly connected displays
        for screen in NSScreen.screens {
            guard let id = screen.displayID, !knownIDs.contains(id) else { continue }
            createDesktopWindow(for: screen)

            // Load current wallpaper on the new display
            if let url = currentWallpaperURL {
                renderers[id]?.loadVideo(url: url)
                if isPlaying {
                    renderers[id]?.play()
                }
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
        stopWatchdog()
        endPlaybackActivity()
        reassertDebounce?.invalidate()
        reassertDebounce = nil
        for observer in reassertObservers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        reassertObservers.removeAll()

        for id in Array(occlusionObservers.keys) {
            removeOcclusionTracking(for: id)
        }

        for renderer in renderers.values {
            renderer.stop()
        }

        for window in desktopWindows.values {
            window.close()
        }

        desktopWindows.removeAll()
        renderers.removeAll()
    }
}
