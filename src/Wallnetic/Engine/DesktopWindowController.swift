import Cocoa
import AVFoundation

/// Controls the desktop-level window that displays live wallpapers behind desktop icons
class DesktopWindowController {
    private var desktopWindows: [NSScreen: NSWindow] = [:]
    private var videoRenderers: [NSScreen: VideoRenderer] = [:]
    private var isPlaying = false

    init() {
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
            defer: false
        )

        // Position window at desktop level (behind icons, above actual desktop)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)

        // Window behavior
        window.collectionBehavior = [
            .canJoinAllSpaces,      // Show on all spaces
            .stationary,             // Don't move with space switches
            .ignoresCycle            // Don't include in Cmd+Tab
        ]

        // Visual properties
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true  // Click-through
        window.acceptsMouseMovedEvents = false

        // Prevent window from being closed/minimized
        window.styleMask.remove(.closable)
        window.styleMask.remove(.miniaturizable)

        // Create and attach video renderer
        let renderer = VideoRenderer()
        window.contentView = renderer.view

        // Store references
        desktopWindows[screen] = window
        videoRenderers[screen] = renderer

        // Show window
        window.orderFront(nil)

        print("Created desktop window for screen: \(screen.localizedName)")
    }

    // MARK: - Playback Control

    /// Sets the wallpaper video for a specific screen
    func setWallpaper(url: URL, for screen: NSScreen? = nil) {
        if let screen = screen {
            // Set for specific screen
            videoRenderers[screen]?.loadVideo(url: url)
        } else {
            // Set for all screens
            for renderer in videoRenderers.values {
                renderer.loadVideo(url: url)
            }
        }
    }

    /// Starts playback on all screens
    func play() {
        isPlaying = true
        for renderer in videoRenderers.values {
            renderer.play()
        }
    }

    /// Pauses playback on all screens
    func pause() {
        isPlaying = false
        for renderer in videoRenderers.values {
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
            desktopWindows[screen]?.close()
            desktopWindows.removeValue(forKey: screen)
            videoRenderers.removeValue(forKey: screen)
            print("Removed desktop window for disconnected screen")
        }

        // Add windows for new screens
        for screen in currentScreens.subtracting(knownScreens) {
            createDesktopWindow(for: screen)
            print("Added desktop window for new screen: \(screen.localizedName)")
        }

        // Update existing windows for resolution changes
        for screen in currentScreens.intersection(knownScreens) {
            if let window = desktopWindows[screen] {
                window.setFrame(screen.frame, display: true)
            }
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        for renderer in videoRenderers.values {
            renderer.stop()
        }

        for window in desktopWindows.values {
            window.close()
        }

        desktopWindows.removeAll()
        videoRenderers.removeAll()
    }
}
