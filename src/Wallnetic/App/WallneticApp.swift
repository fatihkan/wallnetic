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
                .cinematicWindowChrome()
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
