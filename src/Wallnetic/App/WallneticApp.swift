import SwiftUI

/// Shared holder for openWindow — accessible from AppDelegate and DynamicIsland
class WindowManager {
    static let shared = WindowManager()
    var openMainWindow: (() -> Void)?
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
                .onAppear {
                    WindowManager.shared.openMainWindow = { [openWindow] in
                        openWindow(id: "main")
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
        .handlesExternalEvents(matching: [])

        // Settings Window
        Settings {
            SettingsView()
                .environmentObject(wallpaperManager)
        }

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
