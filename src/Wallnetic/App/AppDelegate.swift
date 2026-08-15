import Cocoa
import SwiftUI
import Foundation
import os.log

private let logger = Log.app

class AppDelegate: NSObject, NSApplicationDelegate {
    private var desktopWindowController: DesktopWindowController?
    private var powerManager: PowerManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply dock icon preference
        if UserDefaults.standard.bool(forKey: "hideDockIcon") {
            NSApp.setActivationPolicy(.accessory)
        }

        // Initialize desktop window controller
        desktopWindowController = DesktopWindowController()

        // Wire up PlaybackDelegate — direct calls instead of notification relay (#170)
        WallpaperManager.shared.playbackDelegate = self

        // System wallpaper sync (lock screen / Mission Control still frame).
        // Registered before the delayed wallpaper restore so the restore
        // itself triggers the first sync.
        SystemWallpaperSync.shared.start()

        // Setup power manager with callbacks
        setupPowerManager()

        // Setup display change observer
        setupDisplayObserver()

        // Listen for open main window requests
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenMainWindow),
            name: .openMainWindow,
            object: nil
        )

        // #228: keep the "Hide Dock icon" preference consistent. The app is
        // promoted to .regular whenever a window is shown (so its traffic
        // lights stay active/visible on macOS 26); re-hide (.accessory) once
        // the last normal window closes.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { _ in
            // Defer so the closing window has left NSApp.windows / isVisible.
            DispatchQueue.main.async { DockIconPolicy.reapply() }
        }

        // Drain a review request that had no window to present from. In a
        // menu-bar app that is the usual case, so the ask used to be dropped
        // outright.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { note in
            guard let window = note.object as? NSWindow else { return }
            // Not MainActor.assumeIsolated — that needs macOS 14 and this app
            // targets 13.0. The observer already runs on .main; the hop just
            // gives the compiler the isolation it wants.
            Task { @MainActor in
                RatingPromptManager.shared.windowDidBecomeKey(window)
            }
        }

        // Setup global hotkeys
        setupGlobalHotkeys()

        // Audio visualizer overlay disabled in v1.3.1 — TCC/SCStream UX issues.
        // Files retained for future re-enable; init is gated to skip the
        // lazy singleton allocation so the overlay never auto-restores.
        runAudioVisualizerMigration()

        // Battery prompt (#172) — if we launched while on battery, ask the user
        // whether to keep the live wallpaper running. Delayed so PowerManager
        // has time to detect the initial power state and settings restore.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            BatteryPromptService.shared.checkOnLaunch()
        }

        // App-maturity counter feeding the App Store rating prompt (v1.4 Wave 1).
        RatingPromptManager.shared.recordLaunch()

        // #228: if a normal window auto-opened at launch while "Hide Dock icon"
        // is on, promote back to .regular so its controls are usable; the
        // willClose observer re-hides the icon once it's closed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            DockIconPolicy.reapply()
        }

        logger.info("Wallnetic started successfully")
    }

    // MARK: - Audio Visualizer Migration (v1.3.1)

    /// One-shot migration: turns off the audio visualizer overlay for users
    /// who had it enabled before v1.3.1, where the feature is hidden from
    /// the UI. Re-enabling is a no-op since the migration marker stops
    /// the flag from being touched on subsequent launches.
    private func runAudioVisualizerMigration() {
        let key = "audioVisualizer.migrated.v1.3.1"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(false, forKey: "audioVisualizer.overlayEnabled")
        defaults.set(false, forKey: "audioVisualizer.enabled")
        defaults.set(true, forKey: key)
    }

    // MARK: - Global Hotkeys

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private func setupGlobalHotkeys() {
        guard UserDefaults.standard.bool(forKey: "globalHotkeysEnabled") else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleHotkey(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleHotkey(event) == true { return nil }
            return event
        }
    }

    @discardableResult
    private func handleHotkey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // ⌘⇧→ Next wallpaper
        if flags == [.command, .shift] && event.keyCode == 124 {
            WallpaperManager.shared.cycleToNextWallpaper()
            return true
        }

        // ⌘⇧← Previous wallpaper (#D1: delegate to WallpaperManager directly)
        if flags == [.command, .shift] && event.keyCode == 123 {
            WallpaperManager.shared.cycleToPreviousWallpaper()
            return true
        }

        // ⌘⇧P Toggle play/pause
        if flags == [.command, .shift] && event.charactersIgnoringModifiers == "p" {
            WallpaperManager.shared.togglePlayback()
            return true
        }

        // ⌘⇧R Random wallpaper (#D1: delegate to WallpaperManager directly)
        if flags == [.command, .shift] && event.charactersIgnoringModifiers == "r" {
            WallpaperManager.shared.setRandomWallpaper()
            return true
        }

        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }

        NotificationCenter.default.removeObserver(self)

        powerManager?.cleanup()
        desktopWindowController?.cleanup()

        logger.info("Wallnetic terminating")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Open Main Window

    @objc private func handleOpenMainWindow() {
        showMainWindow()
    }

    private func showMainWindow() {
        if NSApp.activationPolicy() == .accessory {
            NSApp.setActivationPolicy(.regular)
        }

        let existingWindow = NSApp.windows.first { window in
            guard window.level == .normal,
                  !window.title.isEmpty || window.contentView != nil else {
                return false
            }
            return !window.styleMask.contains(.borderless) || window.frame.width >= 800
        }

        if let window = existingWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            WindowManager.shared.openMainWindow?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        // #228: re-hiding the Dock icon (.accessory) is handled centrally by the
        // NSWindow.willCloseNotification observer once the last normal window
        // closes — we must NOT demote while a window is on screen, or its
        // traffic lights render invisible on macOS 26.
    }

    // MARK: - URL Handling

    func application(_ application: NSApplication, open urls: [URL]) {
        // Single entry point: every wallnetic:// URL (widget links AND external
        // deep links) flows through DeepLinkHandler, which centralizes scheme
        // validation, action routing, and the gated/HTTPS-only import path.
        for url in urls {
            DeepLinkHandler.shared.handle(url)
        }
    }

    // MARK: - Power Manager

    private func setupPowerManager() {
        powerManager = PowerManager.shared

        // Keep the widget in step with these pauses. It used to be harmless to
        // skip — power pauses were rare — but screen-lock pausing makes this
        // the common path, and a widget stuck on "playing" reads as a bug.
        powerManager?.onShouldPausePlayback = { [weak self] in
            self?.desktopWindowController?.pause()
            DispatchQueue.main.async {
                WallpaperManager.shared.isPlaying = false
                WidgetSyncService.shared.syncPlaybackState(isPlaying: WallpaperManager.shared.isPlaying)
            }
        }

        powerManager?.onShouldResumePlayback = { [weak self] in
            self?.desktopWindowController?.play()
            DispatchQueue.main.async {
                WallpaperManager.shared.isPlaying = true
                WidgetSyncService.shared.syncPlaybackState(isPlaying: WallpaperManager.shared.isPlaying)
            }
        }
    }

    // MARK: - Display Observer

    private func setupDisplayObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func displaysChanged() {
        Log.app.debug("Display configuration changed")
        desktopWindowController?.handleDisplayChange()
    }
}

// MARK: - PlaybackDelegate (#170)

extension AppDelegate: PlaybackDelegate {
    func playbackSetWallpaper(url: URL) {
        Log.app.debug("PlaybackDelegate: setWallpaper \(url.lastPathComponent, privacy: .public)")
        desktopWindowController?.setWallpaper(url: url)
        if !(powerManager?.shouldBePaused ?? false) {
            desktopWindowController?.play()
        }
    }

    func playbackSetWallpaper(url: URL, for screen: NSScreen) {
        Log.app.debug("PlaybackDelegate: setWallpaper for \(screen.localizedName, privacy: .public)")
        desktopWindowController?.setWallpaper(url: url, for: screen)
        if !(powerManager?.shouldBePaused ?? false) {
            desktopWindowController?.play()
        }
    }

    @discardableResult
    func playbackPlay() -> Bool {
        guard !(powerManager?.shouldBePaused ?? false) else {
            Log.app.info("Play request swallowed — a power condition is active")
            return false
        }
        desktopWindowController?.play()
        return true
    }

    func playbackPause() {
        desktopWindowController?.pause()
    }

    func playbackApplyScreenWallpapers() {
        Log.app.debug("PlaybackDelegate: applyScreenWallpapers")
        for screen in NSScreen.screens {
            if let wallpaper = WallpaperManager.shared.wallpaper(for: screen) {
                desktopWindowController?.setWallpaper(url: wallpaper.url, for: screen)
            }
        }
        if !(powerManager?.shouldBePaused ?? false) {
            desktopWindowController?.play()
        }
    }
}

// MARK: - Dock Icon Policy (#228)

/// Centralizes the "Hide Dock icon" activation-policy logic. Hiding the icon
/// (.accessory) is deferred until no normal window is on screen: an accessory
/// app can't make its window key, which on macOS 26 leaves the traffic-light
/// buttons invisible and the window effectively un-closable.
enum DockIconPolicy {
    /// A normal, titled, visible window — excludes the borderless desktop
    /// render, overlays, the Dynamic Island and the MenuBarExtra.
    static var hasVisibleAppWindow: Bool {
        NSApp.windows.contains {
            $0.isVisible && $0.styleMask.contains(.titled) && $0.level == .normal
        }
    }

    /// Re-applies the saved preference for the current window state.
    static func reapply() {
        let hide = UserDefaults.standard.bool(forKey: "hideDockIcon")
        let target: NSApplication.ActivationPolicy = (hide && !hasVisibleAppWindow) ? .accessory : .regular
        if NSApp.activationPolicy() != target {
            NSApp.setActivationPolicy(target)
        }
    }
}
