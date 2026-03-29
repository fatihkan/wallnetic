import Cocoa
import SwiftUI

/// Floating transparent overlay widget on the desktop
class DesktopOverlayController: ObservableObject {
    static let shared = DesktopOverlayController()

    @AppStorage("overlay.enabled") var isEnabled: Bool = false
    @AppStorage("overlay.showClock") var showClock: Bool = true
    @AppStorage("overlay.showControls") var showControls: Bool = true
    @AppStorage("overlay.opacity") var overlayOpacity: Double = 0.85
    @AppStorage("overlay.posX") var posX: Double = 50
    @AppStorage("overlay.posY") var posY: Double = 50

    @Published var isVisible = false

    private var overlayWindow: NSWindow?

    private init() {
        if isEnabled { show() }
    }

    // MARK: - Show/Hide

    func show() {
        guard overlayWindow == nil else { return }

        let content = DesktopOverlayView()
            .environmentObject(WallpaperManager.shared)
            .environmentObject(self)

        let hostingView = NSHostingView(rootView: content)

        let window = NSPanel(
            contentRect: NSRect(x: posX, y: posY, width: 320, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenNone]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.contentView = hostingView

        window.orderFront(nil)
        overlayWindow = window
        isEnabled = true
        isVisible = true
    }

    func hide() {
        overlayWindow?.close()
        overlayWindow = nil
        isEnabled = false
        isVisible = false
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func savePosition() {
        guard let frame = overlayWindow?.frame else { return }
        posX = Double(frame.origin.x)
        posY = Double(frame.origin.y)
    }
}

// MARK: - Overlay View

struct DesktopOverlayView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @EnvironmentObject var overlayController: DesktopOverlayController

    var body: some View {
        VStack(spacing: 8) {
            if overlayController.showClock {
                // Clock
                Text(timeString)
                    .font(.system(size: 42, weight: .ultraLight, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 2)

                Text(dateString)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }

            if overlayController.showControls {
                HStack(spacing: 16) {
                    // Play/Pause
                    Button {
                        wallpaperManager.togglePlayback()
                    } label: {
                        Image(systemName: wallpaperManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)

                    // Next
                    Button {
                        wallpaperManager.cycleToNextWallpaper()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)

                    // Wallpaper name
                    Text(wallpaperManager.currentWallpaper?.name ?? "")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial.opacity(0.5))
                        .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 0.5))
                )
            }
        }
        .padding(16)
        .opacity(overlayController.overlayOpacity)
    }

    private var timeString: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: Date())
    }

    private var dateString: String {
        let f = DateFormatter(); f.dateFormat = "d MMMM EEEE"
        f.locale = Locale(identifier: "tr_TR")
        return f.string(from: Date())
    }
}
