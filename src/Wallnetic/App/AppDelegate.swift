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

        // Setup wallpaper change observer
        setupWallpaperObserver()

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
        _ = NowPlayingOverlayController.shared
        _ = AudioVisualizerOverlayController.shared

        logger.info("Wallnetic started successfully")
    }

    // MARK: - Wallpaper Observer

    private func setupWallpaperObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(wallpaperDidChange),
            name: .wallpaperDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackStateDidChange),
            name: .playbackStateDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenWallpaperDidChange),
            name: .screenWallpaperDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyScreenWallpapers),
            name: .applyScreenWallpapers,
            object: nil
        )
    }

    @objc private func wallpaperDidChange(_ notification: Notification) {
        guard let wallpaper = notification.object as? Wallpaper else {
            return
        }

        #if DEBUG
        print("[AppDelegate] Applying wallpaper: \(wallpaper.name)")
        #endif

        desktopWindowController?.setWallpaper(url: wallpaper.url)

        // Only play if power conditions allow
        if !(powerManager?.shouldBePaused ?? false) {
            desktopWindowController?.play()
            DispatchQueue.main.async {
                WallpaperManager.shared.isPlaying = true
            }
        }
    }

    @objc private func playbackStateDidChange(_ notification: Notification) {
        guard let isPlaying = notification.object as? Bool else { return }

        if isPlaying {
            // Check power conditions before playing
            if !(powerManager?.shouldBePaused ?? false) {
                desktopWindowController?.play()
            }
        } else {
            desktopWindowController?.pause()
        }
    }

    @objc private func screenWallpaperDidChange(_ notification: Notification) {
        guard let info = notification.object as? ScreenWallpaperInfo else { return }

        #if DEBUG
        print("[AppDelegate] Applying wallpaper '\(info.wallpaper.name)' to screen: \(info.screen.localizedName)")
        #endif

        desktopWindowController?.setWallpaper(url: info.wallpaper.url, for: info.screen)

        // Only play if power conditions allow
        if !(powerManager?.shouldBePaused ?? false) {
            desktopWindowController?.play()
            DispatchQueue.main.async {
                WallpaperManager.shared.isPlaying = true
            }
        }
    }

    @objc private func applyScreenWallpapers() {
        #if DEBUG
        print("[AppDelegate] Applying per-screen wallpapers")
        #endif

        for screen in NSScreen.screens {
            if let wallpaper = WallpaperManager.shared.wallpaper(for: screen) {
                desktopWindowController?.setWallpaper(url: wallpaper.url, for: screen)
            }
        }

        // Only play if power conditions allow
        if !(powerManager?.shouldBePaused ?? false) {
            desktopWindowController?.play()
            DispatchQueue.main.async {
                WallpaperManager.shared.isPlaying = true
            }
        }
    }

    // MARK: - Global Hotkeys

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private func setupGlobalHotkeys() {
        guard UserDefaults.standard.bool(forKey: "globalHotkeysEnabled") else { return }

        // Global monitor (when app is not focused)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleHotkey(event)
        }

        // Local monitor (when app is focused)
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

        // ⌘⇧← Previous wallpaper
        if flags == [.command, .shift] && event.keyCode == 123 {
            cycleToPreviousWallpaper()
            return true
        }

        // ⌘⇧P Toggle play/pause
        if flags == [.command, .shift] && event.charactersIgnoringModifiers == "p" {
            WallpaperManager.shared.togglePlayback()
            return true
        }

        // ⌘⇧R Random wallpaper
        if flags == [.command, .shift] && event.charactersIgnoringModifiers == "r" {
            setRandomWallpaper()
            return true
        }

        return false
    }

    private func cycleToPreviousWallpaper() {
        let wallpapers = WallpaperManager.shared.wallpapers
        guard !wallpapers.isEmpty else { return }
        if let current = WallpaperManager.shared.currentWallpaper,
           let idx = wallpapers.firstIndex(where: { $0.id == current.id }) {
            let prevIdx = (idx - 1 + wallpapers.count) % wallpapers.count
            WallpaperManager.shared.setWallpaper(wallpapers[prevIdx])
        } else if let last = wallpapers.last {
            WallpaperManager.shared.setWallpaper(last)
        }
    }

    private func setRandomWallpaper() {
        let candidates = WallpaperManager.shared.wallpapers.filter {
            $0.id != WallpaperManager.shared.currentWallpaper?.id
        }
        guard let random = candidates.randomElement() else { return }
        WallpaperManager.shared.setWallpaper(random)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Remove hotkey monitors
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }

        // Remove all notification observers
        NotificationCenter.default.removeObserver(self)

        // Cleanup power manager
        powerManager?.cleanup()

        // Cleanup desktop windows
        desktopWindowController?.cleanup()

        logger.info("Wallnetic terminating")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in menu bar even if main window is closed
        return false
    }

    // MARK: - Open Main Window

    @objc private func handleOpenMainWindow() {
        showMainWindow()
    }

    private func showMainWindow() {
        // Temporarily make app regular so windows can appear
        if NSApp.activationPolicy() == .accessory {
            NSApp.setActivationPolicy(.regular)
        }

        // Try existing window first
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
            // No window — use WindowManager to create one via SwiftUI openWindow
            WindowManager.shared.openMainWindow?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        // Re-hide dock after window appears
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
            NSLog("[AppDelegate] Handling URL: %@ (host: %@)", url.absoluteString, host)

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
