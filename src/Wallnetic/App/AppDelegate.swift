import Cocoa
import SwiftUI
import Foundation
import os.log

private let logger = Logger(subsystem: "com.wallnetic.app", category: "AppDelegate")

class AppDelegate: NSObject, NSApplicationDelegate {
    private var desktopWindowController: DesktopWindowController?
    private var powerManager: PowerManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize desktop window controller
        desktopWindowController = DesktopWindowController()

        // Setup wallpaper change observer
        setupWallpaperObserver()

        // Setup power manager with callbacks
        setupPowerManager()

        // Setup display change observer
        setupDisplayObserver()

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

    func applicationWillTerminate(_ notification: Notification) {
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
