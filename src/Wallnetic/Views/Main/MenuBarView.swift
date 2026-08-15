import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @Environment(\.openWindow) var openWindow

    private func openMainWindow() {
        // Check if main window already exists
        let existingWindow = NSApp.windows.first { window in
            // Skip menu bar windows and settings
            guard window.level == .normal,
                  !window.title.isEmpty || window.contentView != nil else {
                return false
            }
            // Check for our main window
            return window.styleMask.contains(.borderless) == false ||
                   window.frame.width >= 800
        }

        if let window = existingWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            // Open new window using WindowGroup ID
            openWindow(id: "main")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Current wallpaper info
            if let current = wallpaperManager.currentWallpaper {
                HStack {
                    Image(systemName: "photo.fill")
                        .foregroundColor(.secondary)
                    Text(current.displayName)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()
            }

            // Playback controls
            Button {
                wallpaperManager.togglePlayback()
            } label: {
                Label(
                    wallpaperManager.isPlaying ? "Pause" : "Play",
                    systemImage: wallpaperManager.isPlaying ? "pause.fill" : "play.fill"
                )
            }
            .keyboardShortcut("p", modifiers: .command)

            Button {
                wallpaperManager.cycleToNextWallpaper()
            } label: {
                Label("Next Wallpaper", systemImage: "forward.fill")
            }
            .keyboardShortcut("n", modifiers: .command)

            // Playlist quick-toggle. The menu is rebuilt on open, so reading
            // the flag directly reflects the current state without observation.
            Button {
                PlaylistManager.shared.toggle()
            } label: {
                Label(
                    PlaylistManager.shared.isEnabled ? "Stop Shuffle" : "Shuffle Wallpapers",
                    systemImage: PlaylistManager.shared.isEnabled ? "shuffle.circle.fill" : "shuffle"
                )
            }

            Divider()

            // Favorites quick-switch
            let favorites = wallpaperManager.wallpapers.filter { $0.isFavorite }
            if !favorites.isEmpty {
                Menu {
                    ForEach(favorites.prefix(6)) { wallpaper in
                        Button {
                            wallpaperManager.setWallpaper(wallpaper)
                        } label: {
                            HStack {
                                Text(wallpaper.displayName)
                                if wallpaper.id == wallpaperManager.currentWallpaper?.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label("Favorites", systemImage: "heart.fill")
                }

                Divider()
            }

            // Quick access
            Button {
                openMainWindow()
            } label: {
                Label("Open Wallnetic", systemImage: "rectangle.on.rectangle")
            }
            .keyboardShortcut("o", modifiers: .command)

            // #228: Settings is a WindowGroup(id:"settings"), not a Settings{}
            // scene — SettingsLink / showPreferencesWindow target the system
            // mechanism that no longer exists, so open the window directly.
            // Activation/dock-icon handling lives in SettingsView.onAppear.
            Button {
                openWindow(id: "settings")
            } label: {
                Label("Settings...", systemImage: "gear")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            // Recent wallpapers submenu
            Menu {
                ForEach(wallpaperManager.wallpapers.prefix(5)) { wallpaper in
                    Button(wallpaper.displayName) {
                        wallpaperManager.setWallpaper(wallpaper)
                    }
                }

                if wallpaperManager.wallpapers.count > 5 {
                    Divider()
                    Text("\(wallpaperManager.wallpapers.count - 5) more...")
                        .foregroundColor(.secondary)
                }
            } label: {
                Label("Recent", systemImage: "clock")
            }

            // Dynamic Island toggle
            Button {
                DynamicIslandController.shared.toggle()
            } label: {
                Label(
                    DynamicIslandController.shared.isVisible ? "Hide Dynamic Island" : "Show Dynamic Island",
                    systemImage: "capsule"
                )
            }

            Divider()

            // Rate, About & Quit.
            //
            // The automatic StoreKit prompt needs a presentable window, which a
            // menu-bar-only user never has, so without this entry they have no
            // route to the App Store at all — the likeliest reason the app sits
            // at zero ratings.
            Button {
                NSWorkspace.shared.open(RatingPromptManager.writeReviewURL)
            } label: {
                Label("Rate Wallnetic", systemImage: "star")
            }

            Button {
                NSApp.orderFrontStandardAboutPanel()
            } label: {
                Label("About Wallnetic", systemImage: "info.circle")
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Wallnetic", systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(WallpaperManager.shared)
        .frame(width: 220)
}
