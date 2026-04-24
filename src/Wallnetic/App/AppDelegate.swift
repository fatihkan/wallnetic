import Cocoa
import SwiftUI
import Foundation
import os.log

private let logger = Logger(subsystem: "com.wallnetic.app", category: "AppDelegate")

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

        // Setup global hotkeys
        setupGlobalHotkeys()

        // Initialize desktop overlays (they self-restore from AppStorage)
        // NowPlayingOverlayController disabled until proper code signing is set up
        _ = AudioVisualizerOverlayController.shared

        // Battery prompt (#172) — if we launched while on battery, ask the user
        // whether to keep the live wallpaper running. Delayed so PowerManager
        // has time to detect the initial power state and settings restore.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            BatteryPromptService.shared.checkOnLaunch()
        }

        logger.info("Wallnetic started successfully")
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if UserDefaults.standard.bool(forKey: "hideDockIcon") {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    // MARK: - URL Handling

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "wallnetic" else { continue }
            let host = url.host ?? ""
            if host == "open" {
                showMainWindow()
            } else if host == "playPause" || host == "nextWallpaper" || host == "setWallpaper" {
                WallpaperManager.shared.handleWidgetURL(url)
            }
        }
    }

    // MARK: - Power Manager

    private func setupPowerManager() {
        powerManager = PowerManager.shared

        powerManager?.onShouldPausePlayback = { [weak self] in
            self?.desktopWindowController?.pause()
            DispatchQueue.main.async {
                WallpaperManager.shared.isPlaying = false
            }
        }

        powerManager?.onShouldResumePlayback = { [weak self] in
            self?.desktopWindowController?.play()
            DispatchQueue.main.async {
                WallpaperManager.shared.isPlaying = true
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
        #if DEBUG
        print("[AppDelegate] Display configuration changed")
        #endif
        desktopWindowController?.handleDisplayChange()
    }
}

// MARK: - PlaybackDelegate (#170)

extension AppDelegate: PlaybackDelegate {
    func playbackSetWallpaper(url: URL) {
        #if DEBUG
        print("[AppDelegate] PlaybackDelegate: setWallpaper \(url.lastPathComponent)")
        #endif
        desktopWindowController?.setWallpaper(url: url)
        if !(powerManager?.shouldBePaused ?? false) {
            desktopWindowController?.play()
        }
    }

    func playbackSetWallpaper(url: URL, for screen: NSScreen) {
        #if DEBUG
        print("[AppDelegate] PlaybackDelegate: setWallpaper for \(screen.localizedName)")
        #endif
        desktopWindowController?.setWallpaper(url: url, for: screen)
        if !(powerManager?.shouldBePaused ?? false) {
            desktopWindowController?.play()
        }
    }

    func playbackPlay() {
        if !(powerManager?.shouldBePaused ?? false) {
            desktopWindowController?.play()
        }
    }

    func playbackPause() {
        desktopWindowController?.pause()
    }

    func playbackApplyScreenWallpapers() {
        #if DEBUG
        print("[AppDelegate] PlaybackDelegate: applyScreenWallpapers")
        #endif
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
