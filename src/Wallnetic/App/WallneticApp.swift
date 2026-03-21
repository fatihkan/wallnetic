import SwiftUI

@main
struct WallneticApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var wallpaperManager = WallpaperManager.shared

    var body: some Scene {
        // Main Window
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(wallpaperManager)
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
