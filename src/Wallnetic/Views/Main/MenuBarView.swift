import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @Environment(\.openWindow) var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Current wallpaper info
            if let current = wallpaperManager.currentWallpaper {
                HStack {
                    Image(systemName: "photo.fill")
                        .foregroundColor(.secondary)
                    Text(current.name)
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

            Divider()

            // Quick access
            Button {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.title == "Wallnetic" }) {
                    window.makeKeyAndOrderFront(nil)
                }
            } label: {
                Label("Open Wallnetic", systemImage: "rectangle.on.rectangle")
            }
            .keyboardShortcut("o", modifiers: .command)

            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Label("Settings...", systemImage: "gear")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            // Recent wallpapers submenu
            Menu {
                ForEach(wallpaperManager.wallpapers.prefix(5)) { wallpaper in
                    Button(wallpaper.name) {
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

            Divider()

            // About & Quit
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
