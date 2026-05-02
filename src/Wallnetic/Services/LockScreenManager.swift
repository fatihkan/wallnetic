import Foundation
import SwiftUI
import AppKit

/// Manages video wallpaper on the lock screen
/// Uses macOS ScreenSaver framework and screen lock/unlock detection
class LockScreenManager: ObservableObject {
    static let shared = LockScreenManager()

    @AppStorage("lockscreen.enabled") var isEnabled: Bool = false
    @AppStorage("lockscreen.wallpaperPath") var wallpaperPath: String = ""
    @AppStorage("lockscreen.showClock") var showClock: Bool = true
    @AppStorage("lockscreen.useCurrentWallpaper") var useCurrentWallpaper: Bool = true

    @Published var isLocked = false

    private var lockObserver: Any?
    private var unlockObserver: Any?
    private var lockScreenWindow: NSWindow?
    private var lockScreenRenderer: VideoRenderer?

    private init() {
        setupObservers()
    }

    // MARK: - Setup

    private func setupObservers() {
        // Detect screen lock
        lockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onScreenLocked()
        }

        // Detect screen unlock
        unlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onScreenUnlocked()
        }
    }

    // MARK: - Lock/Unlock Handlers

    private func onScreenLocked() {
        guard isEnabled else { return }
        isLocked = true
        Log.lockScreen.info("Screen locked - showing video wallpaper")
        showLockScreenWallpaper()
    }

    private func onScreenUnlocked() {
        isLocked = false
        Log.lockScreen.info("Screen unlocked")
        hideLockScreenWallpaper()
    }

    // MARK: - Lock Screen Window

    private func showLockScreenWallpaper() {
        let videoURL: URL?

        if useCurrentWallpaper {
            videoURL = WallpaperManager.shared.currentWallpaper?.url
        } else if !wallpaperPath.isEmpty {
            videoURL = URL(fileURLWithPath: wallpaperPath)
        } else {
            return
        }

        guard let url = videoURL else { return }

        // Create fullscreen window above lock screen level
        guard let screen = NSScreen.main else { return }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        // Position above screen saver but below login window
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = false

        // Create video renderer (must retain — ARC releases it otherwise, stopping playback)
        let renderer = VideoRenderer()
        lockScreenRenderer = renderer
        renderer.rendererView.frame = NSRect(origin: .zero, size: screen.frame.size)
        renderer.rendererView.autoresizingMask = [.width, .height]

        // Add clock overlay if enabled
        if showClock {
            let clockView = NSHostingView(rootView: LockScreenClockView())
            clockView.frame = NSRect(origin: .zero, size: screen.frame.size)
            clockView.autoresizingMask = [.width, .height]

            let containerView = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            containerView.addSubview(renderer.rendererView)
            containerView.addSubview(clockView)
            window.contentView = containerView
        } else {
            window.contentView = renderer.rendererView
        }

        renderer.loadVideo(url: url)
        renderer.play()

        window.orderFront(nil)
        lockScreenWindow = window
    }

    private func hideLockScreenWallpaper() {
        lockScreenRenderer?.stop()
        lockScreenRenderer = nil
        lockScreenWindow?.close()
        lockScreenWindow = nil
    }

    // MARK: - Configuration

    func setLockScreenWallpaper(_ wallpaper: Wallpaper) {
        wallpaperPath = wallpaper.url.path
        useCurrentWallpaper = false
        Log.lockScreen.info("Set lock screen wallpaper: \(wallpaper.name, privacy: .public)")
    }

    func useCurrent() {
        useCurrentWallpaper = true
        wallpaperPath = ""
    }

    deinit {
        if let obs = lockObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
        }
        if let obs = unlockObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
        }
    }
}

// MARK: - Lock Screen Clock

struct LockScreenClockView: View {
    @State private var currentTime = Date()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 8) {
                Text(timeString)
                    .font(.system(size: 80, weight: .thin, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 4)

                Text(dateString)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .shadow(color: .black.opacity(0.4), radius: 6)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onReceive(timer) { time in
            currentTime = time
        }
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: currentTime)
    }

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMMM"
        f.locale = Locale.current
        return f.string(from: currentTime)
    }
}
