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
    /// True while the login window covers the session (screen locked) or another
    /// user is switched in. Nothing the user can see is on screen, but without
    /// this the decoder ran at full rate the whole time.
    private(set) var isSessionInactive = false

    private var fullscreenCheckTimer: Timer?
    private var powerSourceRef: CFRunLoopSource?

    /// False until `init` finishes seeding initial state. Used to suppress
    /// the first-pass BatteryPromptService trigger — launch-time prompting is
    /// owned by AppDelegate's delayed `checkOnLaunch()` so we don't race the
    /// wallpaper restore.
    private var isInitialized = false

    private init() {
        setupObservers()
        checkInitialPowerState()
        isInitialized = true
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
        DistributedNotificationCenter.default().removeObserver(self)

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

        // Screen saver + screen lock. These are cross-process names posted by
        // loginwindow/screensaver, so they only ever arrive on the *distributed*
        // center — registering them on NotificationCenter.default (as this did
        // until v1.4.1) meant they could never fire and the screen-saver branch
        // of `shouldBePaused` was unreachable.
        //
        // `.deliverImmediately` is load-bearing: the convenience overload
        // defaults to `.coalesce`, and AppKit suspends distributed delivery
        // while the app is inactive — which it always is when the screen locks
        // or the saver starts.
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(
            self,
            selector: #selector(screenSaverDidStart),
            name: NSNotification.Name("com.apple.screensaver.didstart"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        dnc.addObserver(
            self,
            selector: #selector(screenSaverDidStop),
            name: NSNotification.Name("com.apple.screensaver.didstop"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        dnc.addObserver(
            self,
            selector: #selector(screenDidLock),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        dnc.addObserver(
            self,
            selector: #selector(screenDidUnlock),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        // Fast user switching — the other user keeps the display awake, so no
        // sleep or lock notification ever arrives to stop us.
        wsnc.addObserver(
            self,
            selector: #selector(sessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )

        wsnc.addObserver(
            self,
            selector: #selector(sessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
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
            Log.power.info("Low Power Mode enabled")
            notifyPauseIfNeeded()
        } else if !isLowPowerMode && wasLowPower {
            Log.power.info("Low Power Mode disabled")
            notifyResumeIfNeeded()
        }
    }

    private func handlePowerSourceChange() {
        if isOnBattery {
            Log.power.info("Switched to battery power")
            if BatteryPromptService.shared.effectivePauseOnBattery {
                notifyPauseIfNeeded()
            }
            // Only prompt on genuine runtime transitions — launch-time prompts
            // are handled by AppDelegate.checkOnLaunch after restore settles.
            if isInitialized {
                BatteryPromptService.shared.onSwitchedToBattery()
            }
        } else {
            Log.power.info("Switched to AC power")
            notifyResumeIfNeeded()
        }
    }

    private func handleFullscreenChange() {
        if isFullscreenAppActive {
            Log.power.info("Fullscreen app detected")
            if WallpaperManager.shared.pauseOnFullscreen {
                notifyPauseIfNeeded()
            }
        } else {
            Log.power.info("Fullscreen app closed")
            notifyResumeIfNeeded()
        }
    }

    @objc private func screensDidSleep() {
        Log.power.info("Screens did sleep")
        isScreenAsleep = true
        notifyPauseIfNeeded()
    }

    @objc private func screensDidWake() {
        Log.power.info("Screens did wake")
        isScreenAsleep = false
        resyncSessionState()
        notifyResumeIfNeeded(respectAutoResume: false)
    }

    @objc private func systemWillSleep() {
        Log.power.info("System will sleep")
        notifyPauseIfNeeded()
    }

    @objc private func systemDidWake() {
        Log.power.info("System did wake")
        // Small delay to let system stabilize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.resyncSessionState()
            self.notifyResumeIfNeeded(respectAutoResume: false)
        }
    }

    @objc private func screenSaverDidStart() {
        Log.power.info("Screen saver started")
        isScreenSaverActive = true
        notifyPauseIfNeeded()
    }

    @objc private func screenSaverDidStop() {
        Log.power.info("Screen saver stopped")
        isScreenSaverActive = false
        resyncSessionState()
        notifyResumeIfNeeded(respectAutoResume: false)
    }

    @objc private func screenDidLock() {
        Log.power.info("Screen locked")
        isSessionInactive = true
        notifyPauseIfNeeded()
    }

    @objc private func screenDidUnlock() {
        Log.power.info("Screen unlocked")
        isSessionInactive = false
        resyncSessionState()
        notifyResumeIfNeeded(respectAutoResume: false)
    }

    @objc private func sessionDidResignActive() {
        Log.power.info("Session switched away (fast user switching)")
        isSessionInactive = true
        notifyPauseIfNeeded()
    }

    @objc private func sessionDidBecomeActive() {
        Log.power.info("Session became active")
        isSessionInactive = false
        resyncSessionState()
        notifyResumeIfNeeded(respectAutoResume: false)
    }

    /// Re-derives lock / session state from the window server rather than
    /// trusting a matched pair of notifications to always arrive.
    ///
    /// Without this a single missed unlock — screensaver into display sleep
    /// waking to a lock screen, unlocking straight into a user switch, a
    /// `distnoted` restart — would leave `shouldBePaused` true forever, and the
    /// playback watchdog deliberately stands down while paused. The wallpaper
    /// would simply never come back, which is precisely the "it froze, I had to
    /// reopen it" complaint the watchdog exists to kill.
    private func resyncSessionState() {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return }
        let onConsole = session["kCGSSessionOnConsoleKey"] as? Bool ?? true
        let locked = session["CGSSessionScreenIsLocked"] as? Bool ?? false
        isSessionInactive = !onConsole || locked
        // A saver that stopped without posting .didstop can't strand us either.
        if !locked {
            isScreenSaverActive = false
        }
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

    /// True only while playback is paused *by this manager*. See
    /// ``PowerPauseOwnership`` for why this exists.
    private var pausedByPower = false

    /// Hands playback ownership back to the user. Called when they explicitly
    /// press Play or Pause, after which no power event may override them until
    /// we pause again ourselves.
    func userDidTogglePlayback() {
        pausedByPower = false
    }

    private func notifyPauseIfNeeded() {
        if PowerPauseOwnership.shouldClaimPause(
            wallpaperIsPlaying: WallpaperManager.shared.isPlaying
        ) {
            pausedByPower = true
        }
        let callback = onShouldPausePlayback
        runOnMain { callback?() }
    }

    /// - Parameter respectAutoResume: pass `false` for pauses the user never
    ///   asked for (lock, user switch, screen saver, wake). "Don't auto-resume"
    ///   is about battery and fullscreen pauses; applying it to a screen lock
    ///   would leave the wallpaper dead after every unlock.
    private func notifyResumeIfNeeded(respectAutoResume: Bool = true) {
        guard PowerPauseOwnership.shouldResume(
            pausedByPower: pausedByPower,
            shouldBePaused: shouldBePaused,
            respectAutoResume: respectAutoResume,
            autoResumeEnabled: WallpaperManager.shared.shouldAutoResume
        ) else { return }

        pausedByPower = false
        let callback = onShouldResumePlayback
        runOnMain { callback?() }
    }

    /// Routes playback callbacks to the main thread before they touch
    /// AppKit/AVKit (NSWindow, AVPlayer-on-view). Sleep/wake, screen-parameter
    /// and IOPS battery notifications already arrive on main and run
    /// synchronously here; only NSProcessInfoPowerStateDidChange (Low Power
    /// Mode) is not guaranteed main-thread, so it hops via async. [#206]
    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    /// Returns true if playback should be paused based on current conditions
    var shouldBePaused: Bool {
        if isScreenAsleep || isScreenSaverActive || isSessionInactive {
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
