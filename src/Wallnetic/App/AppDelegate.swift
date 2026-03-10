import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var desktopWindowController: DesktopWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize desktop window controller
        desktopWindowController = DesktopWindowController()

        // Setup power state observer
        setupPowerObserver()

        // Setup display change observer
        setupDisplayObserver()

        // Hide dock icon if running as menu bar only (optional)
        // NSApp.setActivationPolicy(.accessory)

        print("Wallnetic started successfully")
    }

    func applicationWillTerminate(_ notification: Notification) {
        desktopWindowController?.cleanup()
        print("Wallnetic terminating")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in menu bar even if main window is closed
        return false
    }

    // MARK: - Power Observer

    private func setupPowerObserver() {
        // Observe low power mode
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateChanged),
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
    }

    @objc private func powerStateChanged() {
        let isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        if isLowPowerMode {
            desktopWindowController?.pausePlayback()
            print("Low Power Mode enabled - pausing playback")
        } else {
            desktopWindowController?.resumePlayback()
            print("Low Power Mode disabled - resuming playback")
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
        print("Display configuration changed")
        desktopWindowController?.handleDisplayChange()
    }
}
