import SwiftUI

/// Routes every Library entry point to a window registered by the main scene.
/// Weak membership preserves SwiftUI's window ownership and identifiers.
class WindowManager {
    static let shared = WindowManager()
    var openMainWindow: (() -> Void)?
    private let mainWindows = NSHashTable<NSWindow>.weakObjects()
    private var closeObserver: NSObjectProtocol?

    init() {
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            self?.mainWindows.remove(window)
        }
    }

    deinit {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
    }

    func registerMainWindow(_ window: NSWindow) {
        guard window.styleMask.contains(.titled),
              !(window is NSPanel), !window.isSheet else { return }
        mainWindows.add(window)
    }

    func mainWindow(in windows: [NSWindow]) -> NSWindow? {
        windows.first {
            mainWindows.contains($0) && $0.level == .normal &&
            $0.styleMask.contains(.titled) && !($0 is NSPanel) && !$0.isSheet
        }
    }

    func showMainWindow(openScene: (() -> Void)? = nil) {
        if NSApp.activationPolicy() == .accessory {
            NSApp.setActivationPolicy(.regular)
        }
        if let window = mainWindow(in: NSApp.windows) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            (openScene ?? openMainWindow)?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        // DockIconPolicy restores the preference after the last normal window closes.
    }
}

@main
struct WallneticApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var wallpaperManager = WallpaperManager.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Main Window
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(wallpaperManager)
                .cinematicWindowChrome(isMainWindow: true)
                .onAppear {
                    WindowManager.shared.openMainWindow = { [openWindow] in
                        openWindow(id: "main")
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Playback") {
                CalmModeButton(settings: .shared)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    openWindow(id: "settings")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        .handlesExternalEvents(matching: [])

        // Keep native window controls in their own title bar on both scenes.
        // We wire ⌘, manually to this settings WindowGroup.
        WindowGroup(id: "settings") {
            SettingsView()
                .environmentObject(wallpaperManager)
                .cinematicWindowChrome()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .handlesExternalEvents(matching: [])

        // Menu Bar Extra
        MenuBarExtra {
            MenuBarView()
                .environmentObject(wallpaperManager)
        } label: {
            Image(systemName: "photo.on.rectangle.angled")
        }
        .menuBarExtraStyle(.menu)
    }
}
