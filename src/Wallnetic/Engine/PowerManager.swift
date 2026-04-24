import Cocoa
import IOKit.ps
import IOKit.pwr_mgt

/// Manages power-related events and optimizations for wallpaper playback
class PowerManager {
    static let shared = PowerManager()

    // Callbacks
    var onShouldPausePlayback: (() -> Void)?
    var onShouldResumePlayback: (() -> Void)?

    private let fullscreenQueue = DispatchQueue(label: "com.wallnetic.power.fullscreen", qos: .utility)

    // State tracking
    private(set) var isOnBattery = false
    private(set) var isLowPowerMode = false
    private(set) var isFullscreenAppActive = false
    private(set) var isScreenAsleep = false
    private(set) var isScreenSaverActive = false

    private var fullscreenCheckTimer: Timer?
    private var powerSourceRef: CFRunLoopSource?

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

        // Stop debounce timer
        fullscreenDebounceTimer?.invalidate()
        fullscreenDebounceTimer = nil

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
            powerSourceRef = source
        }
    }

    private func removePowerSourceObserver() {
        if let source = powerSourceRef {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        powerSourceRef = nil
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

    private var fullscreenDebounceTimer: Timer?

    private func checkFullscreenApps() {
        // Capture values that are safe to read on main thread.
        let frontApp = NSWorkspace.shared.frontmostApplication
        let wasFullscreen = isFullscreenAppActive
        let screens = NSScreen.screens.map { $0.frame }

        // Run the expensive CGWindowListCopyWindowInfo off the main thread.
        fullscreenQueue.async { [weak self] in
            guard let self else { return }

            guard let frontApp else {
                DispatchQueue.main.async { self.updateFullscreenState(false, wasFullscreen: wasFullscreen) }
                return
            }

            let skipBundleIds = [
                Bundle.main.bundleIdentifier,
                "com.apple.finder",
                "com.apple.dock",
                "com.apple.SystemUIServer",
                "com.apple.controlcenter",
                "com.apple.notificationcenterui"
            ]

            if skipBundleIds.contains(frontApp.bundleIdentifier) {
                DispatchQueue.main.async { self.updateFullscreenState(false, wasFullscreen: wasFullscreen) }
                return
            }

            let options = CGWindowListOption.optionOnScreenOnly
            let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

            let appWindows = windowList.filter { windowInfo in
                guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? Int32 else {
                    return false
                }
                return ownerPID == frontApp.processIdentifier
            }

            let hasFullscreenWindow = appWindows.contains { windowInfo in
                guard let layer = windowInfo[kCGWindowLayer as String] as? Int,
                      layer == 0,
                      let bounds = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] else {
                    return false
                }

                let windowX = bounds["X"] ?? 0
                let windowY = bounds["Y"] ?? 0
                let windowWidth = bounds["Width"] ?? 0
                let windowHeight = bounds["Height"] ?? 0

                return screens.contains { screenFrame in
                    let xMatches = abs(windowX - screenFrame.origin.x) < 2
                    let yMatches = abs(windowY - screenFrame.origin.y) < 2
                    let widthMatches = abs(windowWidth - screenFrame.width) < 2
                    let heightMatches = abs(windowHeight - screenFrame.height) < 2
                    return xMatches && yMatches && widthMatches && heightMatches
                }
            }

            DispatchQueue.main.async {
                self.updateFullscreenState(hasFullscreenWindow, wasFullscreen: wasFullscreen)
            }
        }
    }

    private func updateFullscreenState(_ newState: Bool, wasFullscreen: Bool) {
        isFullscreenAppActive = newState

        if wasFullscreen != isFullscreenAppActive {
            // Debounce to prevent rapid state changes
            fullscreenDebounceTimer?.invalidate()
            fullscreenDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                self?.handleFullscreenChange()
            }
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
            if BatteryPromptService.shared.effectivePauseOnBattery {
                notifyPauseIfNeeded()
            }
            BatteryPromptService.shared.onSwitchedToBattery()
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

        if isOnBattery && BatteryPromptService.shared.effectivePauseOnBattery {
            return true
        }

        if isFullscreenAppActive && WallpaperManager.shared.pauseOnFullscreen {
            return true
        }

        return false
    }
}
