import Cocoa
import IOKit.ps
import IOKit.pwr_mgt

/// Manages power-related events and optimizations for wallpaper playback
class PowerManager {
    static let shared = PowerManager()

    // Callbacks
    var onShouldPausePlayback: (() -> Void)?
    var onShouldResumePlayback: (() -> Void)?

    // State tracking
    private(set) var isOnBattery = false
    private(set) var isLowPowerMode = false
    private(set) var isFullscreenAppActive = false
    private(set) var isScreenAsleep = false
    private(set) var isScreenSaverActive = false

    private var fullscreenCheckTimer: Timer?
    private var powerSource: Unmanaged<CFRunLoopSource>?

    private init() {
        setupObservers()
        checkInitialPowerState()
        startFullscreenMonitoring()
    }

    deinit {
        cleanup()
    }

    /// Removes all observers and timers
    func cleanup() {
        // Stop fullscreen monitoring timer
        stopFullscreenMonitoring()

        // Remove power source observer
        removePowerSourceObserver()

        // Remove all notification observers
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)

        // Clear callbacks to break retain cycles
        onShouldPausePlayback = nil
        onShouldResumePlayback = nil
    }

    // MARK: - Setup

    private func setupObservers() {
        let nc = NotificationCenter.default
        let wsnc = NSWorkspace.shared.notificationCenter

        // Low power mode
        nc.addObserver(
            self,
            selector: #selector(powerStateChanged),
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )

        // Screen sleep/wake
        wsnc.addObserver(
            self,
            selector: #selector(screensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )

        wsnc.addObserver(
            self,
            selector: #selector(screensDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )

        // System sleep/wake
        wsnc.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        wsnc.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        // Screen saver
        nc.addObserver(
            self,
            selector: #selector(screenSaverDidStart),
            name: NSNotification.Name("com.apple.screensaver.didstart"),
            object: nil
        )

        nc.addObserver(
            self,
            selector: #selector(screenSaverDidStop),
            name: NSNotification.Name("com.apple.screensaver.didstop"),
            object: nil
        )

        // Active space changed (for fullscreen detection)
        wsnc.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        // App activation changes
        wsnc.addObserver(
            self,
            selector: #selector(appDidActivate),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // Setup power source observer
        setupPowerSourceObserver()
    }

    private func checkInitialPowerState() {
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        checkBatteryState()
    }

    // MARK: - Power Source Monitoring

    private func setupPowerSourceObserver() {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context = context else { return }
            let manager = Unmanaged<PowerManager>.fromOpaque(context).takeUnretainedValue()
            manager.checkBatteryState()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = Unmanaged.passRetained(source)
        }
    }

    private func removePowerSourceObserver() {
        if let source = powerSource?.takeUnretainedValue() {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        powerSource = nil
    }

    private func checkBatteryState() {
        let wasOnBattery = isOnBattery

        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
           !sources.isEmpty {
            // Check power source type
            if let source = IOPSGetPowerSourceDescription(info, sources[0])?.takeUnretainedValue() as? [String: Any] {
                let powerSourceState = source[kIOPSPowerSourceStateKey as String] as? String
                isOnBattery = powerSourceState == kIOPSBatteryPowerValue
            }
        }

        if wasOnBattery != isOnBattery {
            handlePowerSourceChange()
        }
    }

    // MARK: - Fullscreen Detection

    private func startFullscreenMonitoring() {
        // Check periodically for fullscreen apps (more reliable than notifications alone)
        fullscreenCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkFullscreenApps()
        }
    }

    private func stopFullscreenMonitoring() {
        fullscreenCheckTimer?.invalidate()
        fullscreenCheckTimer = nil
    }

    private func checkFullscreenApps() {
        let wasFullscreen = isFullscreenAppActive

        // Get the frontmost app's windows
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            isFullscreenAppActive = false
            if wasFullscreen != isFullscreenAppActive {
                handleFullscreenChange()
            }
            return
        }

        // Skip our own app and Finder (desktop)
        let skipBundleIds = [
            Bundle.main.bundleIdentifier,
            "com.apple.finder",
            "com.apple.dock",
            "com.apple.SystemUIServer",
            "com.apple.controlcenter"
        ]

        if skipBundleIds.contains(frontApp.bundleIdentifier) {
            isFullscreenAppActive = false
            if wasFullscreen != isFullscreenAppActive {
                handleFullscreenChange()
            }
            return
        }

        // Check if the frontmost app has a fullscreen window using NSApp presentation options
        // This is more reliable than checking window bounds
        let options = CGWindowListOption.optionOnScreenOnly
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

        isFullscreenAppActive = windowList.contains { windowInfo in
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == frontApp.processIdentifier,
                  let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer == 0,  // Normal window layer
                  let bounds = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] else {
                return false
            }

            let windowWidth = bounds["Width"] ?? 0
            let windowHeight = bounds["Height"] ?? 0

            // Check if window matches any screen size exactly (with small tolerance for menu bar)
            return NSScreen.screens.contains { screen in
                let screenWidth = screen.frame.width
                let screenHeight = screen.frame.height
                let visibleHeight = screen.visibleFrame.height

                // Window must match screen width exactly and height should be full screen
                // (either with or without menu bar)
                let widthMatches = abs(windowWidth - screenWidth) < 2
                let heightMatchesFull = abs(windowHeight - screenHeight) < 2
                let heightMatchesVisible = abs(windowHeight - visibleHeight) < 2

                return widthMatches && (heightMatchesFull || (heightMatchesVisible && windowHeight > screenHeight * 0.9))
            }
        }

        if wasFullscreen != isFullscreenAppActive {
            handleFullscreenChange()
        }
    }

    // MARK: - Event Handlers

    @objc private func powerStateChanged() {
        let wasLowPower = isLowPowerMode
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        if isLowPowerMode && !wasLowPower {
            print("[PowerManager] Low Power Mode enabled")
            notifyPauseIfNeeded()
        } else if !isLowPowerMode && wasLowPower {
            print("[PowerManager] Low Power Mode disabled")
            notifyResumeIfNeeded()
        }
    }

    private func handlePowerSourceChange() {
        if isOnBattery {
            print("[PowerManager] Switched to battery power")
            if WallpaperManager.shared.pauseOnBattery {
                notifyPauseIfNeeded()
            }
        } else {
            print("[PowerManager] Switched to AC power")
            notifyResumeIfNeeded()
        }
    }

    private func handleFullscreenChange() {
        if isFullscreenAppActive {
            print("[PowerManager] Fullscreen app detected")
            if WallpaperManager.shared.pauseOnFullscreen {
                notifyPauseIfNeeded()
            }
        } else {
            print("[PowerManager] Fullscreen app closed")
            notifyResumeIfNeeded()
        }
    }

    @objc private func screensDidSleep() {
        print("[PowerManager] Screens did sleep")
        isScreenAsleep = true
        notifyPauseIfNeeded()
    }

    @objc private func screensDidWake() {
        print("[PowerManager] Screens did wake")
        isScreenAsleep = false
        notifyResumeIfNeeded()
    }

    @objc private func systemWillSleep() {
        print("[PowerManager] System will sleep")
        notifyPauseIfNeeded()
    }

    @objc private func systemDidWake() {
        print("[PowerManager] System did wake")
        // Small delay to let system stabilize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.notifyResumeIfNeeded()
        }
    }

    @objc private func screenSaverDidStart() {
        print("[PowerManager] Screen saver started")
        isScreenSaverActive = true
        notifyPauseIfNeeded()
    }

    @objc private func screenSaverDidStop() {
        print("[PowerManager] Screen saver stopped")
        isScreenSaverActive = false
        notifyResumeIfNeeded()
    }

    @objc private func activeSpaceDidChange() {
        // Recheck fullscreen status when space changes
        checkFullscreenApps()
    }

    @objc private func appDidActivate(_ notification: Notification) {
        // Recheck fullscreen status when app changes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.checkFullscreenApps()
        }
    }

    // MARK: - Notifications

    private func notifyPauseIfNeeded() {
        onShouldPausePlayback?()
    }

    private func notifyResumeIfNeeded() {
        // Only resume if all conditions are clear
        guard !shouldBePaused else { return }

        if WallpaperManager.shared.shouldAutoResume {
            onShouldResumePlayback?()
        }
    }

    /// Returns true if playback should be paused based on current conditions
    var shouldBePaused: Bool {
        if isScreenAsleep || isScreenSaverActive {
            return true
        }

        if isLowPowerMode {
            return true
        }

        if isOnBattery && WallpaperManager.shared.pauseOnBattery {
            return true
        }

        if isFullscreenAppActive && WallpaperManager.shared.pauseOnFullscreen {
            return true
        }

        return false
    }
}
