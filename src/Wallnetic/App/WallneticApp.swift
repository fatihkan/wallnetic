import SwiftUI

@main
struct WallneticApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var wallpaperManager = WallpaperManager.shared

    var body: some Scene {
        // Main Window
        WindowGroup {
            ContentView()
                .environmentObject(wallpaperManager)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

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
