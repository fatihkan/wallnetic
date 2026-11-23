import SwiftUI

/// The menu bar menu holds the essentials (#343 B4): what each display is
/// doing, Play/Pause, Calm Mode, Next, the main window, Settings, Rate and
/// Quit. The playlist switch, favourites, the Dynamic Island switch and
/// About live in the main window and in Settings.
struct MenuBarView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @Environment(\.openWindow) var openWindow
    @ObservedObject private var performance = PerformanceManager.shared

    private func openMainWindow() {
        WindowManager.shared.showMainWindow {
            openWindow(id: "main")
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
            ForEach(wallpaperManager.displayPlaybackStatuses) { status in
                Menu {
                    Text(status.title)
                    if !status.detail.isEmpty { Text(status.detail) }
                    if status.canRetry {
                        Button("Retry wallpaper") { wallpaperManager.retryWallpaper(on: status.id) }
                            .accessibilityLabel("Retry wallpaper on \(status.displayName)")
                    }
                } label: {
                    Label("\(status.displayName): \(status.title)", systemImage: status.symbol)
                }
                .accessibilityLabel("\(status.displayName): \(status.title)")
            }
            Text("Playback profile: \(performance.mode.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            Button {
                wallpaperManager.togglePlayback()
            } label: {
                Label(
                    wallpaperManager.isPlaying ? "Pause" : "Play",
                    systemImage: wallpaperManager.isPlaying ? "pause.fill" : "play.fill"
                )
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(!wallpaperManager.isPlaying &&
                wallpaperManager.displayPlaybackStatuses.contains(where: \.blocksResume))

            CalmModeButton(settings: .shared)

            Button {
                wallpaperManager.cycleToNextWallpaper()
            } label: {
                Label("Next Wallpaper", systemImage: "forward.fill")
            }
            .keyboardShortcut("n", modifiers: .command)

            Divider()

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
                Label("Settings…", systemImage: "gear")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            // Rate & Quit.
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
