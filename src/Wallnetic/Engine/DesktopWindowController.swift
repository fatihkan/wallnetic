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
    private var desktopWindows: [NSScreen: NSWindow] = [:]
    private var renderers: [NSScreen: WallpaperRenderer] = [:]
    private var effectOverlays: [NSScreen: NSView] = [:]
    private var isPlaying = false
    private var currentWallpaperURL: URL?
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
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: true  // Defer creation for performance
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

        // Visual properties - optimized for performance
        window.isOpaque = true  // Opaque is faster than transparent
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.acceptsMouseMovedEvents = false
        window.isReleasedWhenClosed = false

        // Disable window animations
        window.animationBehavior = .none

        // Prevent window from being closed/minimized
        window.styleMask.remove(.closable)
        window.styleMask.remove(.miniaturizable)

        // Create and attach video renderer (Metal or AVFoundation based)
        let renderer: WallpaperRenderer
        if useMetalRenderer {
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
        effectOverlays[screen] = effectOverlay

        // Store references
        desktopWindows[screen] = window
        renderers[screen] = renderer

        // Apply current effects
        applyEffectsToOverlay(effectOverlay)

        // Show window
        window.orderFront(nil)

        #if DEBUG
        print("[DesktopWindow] Created window for: \(screen.localizedName) using \(useMetalRenderer ? "Metal" : "AVFoundation") renderer")
        #endif
    }

    // MARK: - Playback Control

    /// Sets the wallpaper video with animated transition
    func setWallpaper(url: URL, for screen: NSScreen? = nil) {
        guard url != currentWallpaperURL else { return }
        currentWallpaperURL = url

        let style = WallpaperManager.shared.transitionStyle
        let duration = WallpaperManager.shared.transitionDuration
        let screens = screen.map { [$0] } ?? Array(desktopWindows.keys)

        for s in screens {
            guard let window = desktopWindows[s],
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
        let currentScreens = Set(NSScreen.screens)
        let knownScreens = Set(desktopWindows.keys)

        // Remove windows for disconnected screens
        for screen in knownScreens.subtracting(currentScreens) {
            renderers[screen]?.stop()
            desktopWindows[screen]?.close()
            desktopWindows.removeValue(forKey: screen)
            renderers.removeValue(forKey: screen)
        }

        // Add windows for new screens
        for screen in currentScreens.subtracting(knownScreens) {
            createDesktopWindow(for: screen)

            // Load current wallpaper on new screen
            if let url = currentWallpaperURL {
                renderers[screen]?.loadVideo(url: url)
                if isPlaying {
                    renderers[screen]?.play()
                }
            }
        }

        // Update existing windows for resolution changes
        for screen in currentScreens.intersection(knownScreens) {
            if let window = desktopWindows[screen] {
                window.setFrame(screen.frame, display: false)
            }
        }
    }

    // MARK: - Effects

    /// Applies current effects to all screen overlays
    func applyEffects() {
        for (screen, overlay) in effectOverlays {
            applyEffectsToOverlay(overlay)
            // Apply blur to the renderer view's layer
            if let renderer = renderers[screen] {
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
