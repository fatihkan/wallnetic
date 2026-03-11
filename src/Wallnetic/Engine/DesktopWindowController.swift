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
    private var isPlaying = false
    private var currentWallpaperURL: URL?
    private var useMetalRenderer: Bool

    init() {
        // Check if Metal renderer should be used
        self.useMetalRenderer = WallpaperManager.shared.useMetalRenderer
        setupDesktopWindows()
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

        // Store references
        desktopWindows[screen] = window
        renderers[screen] = renderer

        // Show window
        window.orderFront(nil)

        #if DEBUG
        print("[DesktopWindow] Created window for: \(screen.localizedName) using \(useMetalRenderer ? "Metal" : "AVFoundation") renderer")
        #endif
    }

    // MARK: - Playback Control

    /// Sets the wallpaper video for a specific screen
    func setWallpaper(url: URL, for screen: NSScreen? = nil) {
        currentWallpaperURL = url

        if let screen = screen {
            renderers[screen]?.loadVideo(url: url)
        } else {
            // Set for all screens
            for renderer in renderers.values {
                renderer.loadVideo(url: url)
            }
        }
    }

    /// Starts playback on all screens
    func play() {
        guard !isPlaying else { return }

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
