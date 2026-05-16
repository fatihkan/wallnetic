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
        .windowStyle(.hiddenTitleBar)
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

        // Settings Window — own WindowGroup so .windowStyle(.hiddenTitleBar)
        // actually applies (`Settings {}` scene resists it). We wire ⌘,
        // manually so the keyboard shortcut and menu item still work.
        WindowGroup(id: "settings") {
            SettingsView()
                .environmentObject(wallpaperManager)
                .cinematicWindowChrome()
        }
        .windowStyle(.hiddenTitleBar)
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
