import Cocoa
import AVFoundation

/// Protocol for video renderers (supports both AVFoundation and Metal-based renderers)
protocol WallpaperRenderer {
    var rendererView: NSView { get }
    func loadVideo(url: URL)
    func play()
    func pause()
    func stop()
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

    init() {
        self.useMetalRenderer = WallpaperManager.shared.useMetalRenderer
        setupDesktopWindows()
        setupEffectsObserver()
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
        let window = OverlayWindowFactory.makeBackgroundWindow(contentRect: screen.frame)

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
        window.contentView = renderer.rendererView

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

        // Apply current effects
        applyEffectsToOverlay(effectOverlay)

        // Show window
        window.orderFront(nil)

        let rendererName = useMetalRenderer ? "Metal" : "AVFoundation"
        Log.window.debug("Created window for: \(screen.localizedName, privacy: .public) using \(rendererName, privacy: .public) renderer")
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

        let style = WallpaperManager.shared.transitionStyle
        let duration = WallpaperManager.shared.transitionDuration
        let displayIDs = targetID.map { [$0] } ?? Array(desktopWindows.keys)

        for s in displayIDs {
            // Window presence gates the apply; the renderer does the work.
            guard desktopWindows[s] != nil,
                  let renderer = renderers[s] else { continue }

            // No transition — instant switch
            if style == "none" {
                renderer.loadVideo(url: url)
                continue
            }

            // Use CATransition on the renderer layer for reliable animation
            let transition = CATransition()
            transition.duration = duration
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            switch style {
            case "zoom":
                transition.type = .reveal
                transition.subtype = .fromBottom
            case "slide":
                transition.type = .push
                transition.subtype = .fromRight
            default:
                transition.type = .fade
            }

            renderer.rendererView.layer?.add(transition, forKey: "wallpaperTransition")
            renderer.loadVideo(url: url)
        }
    }

    /// Starts playback on all screens
    func play() {
        isPlaying = true
        for renderer in renderers.values {
            renderer.play()
        }
    }

    /// Pauses playback on all screens
    func pause() {
        guard isPlaying else { return }

        isPlaying = false
        for renderer in renderers.values {
            renderer.pause()
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

    // MARK: - Display Changes

    /// Handles display configuration changes (connect/disconnect monitors)
    func handleDisplayChange() {
        let currentIDs = Set(NSScreen.screens.compactMap { $0.displayID })
        let knownIDs = Set(desktopWindows.keys)

        // Remove windows for disconnected displays
        for id in knownIDs.subtracting(currentIDs) {
            renderers[id]?.stop()
            desktopWindows[id]?.close()
            desktopWindows.removeValue(forKey: id)
            renderers.removeValue(forKey: id)
            effectOverlays.removeValue(forKey: id)
            screenWallpaperURLs.removeValue(forKey: id)
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
        }

        // Update existing windows for resolution / arrangement changes
        for screen in NSScreen.screens {
            guard let id = screen.displayID, let window = desktopWindows[id] else { continue }
            window.setFrame(screen.frame, display: false)
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
                let layer = renderer.rendererView.layer

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
