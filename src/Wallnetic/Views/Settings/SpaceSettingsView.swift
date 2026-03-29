import SwiftUI

/// Settings for per-Space wallpaper and Lock Screen
struct SpaceSettingsView: View {
    @ObservedObject private var spaceManager = SpaceWallpaperManager.shared
    @ObservedObject private var lockManager = LockScreenManager.shared
    @EnvironmentObject var wallpaperManager: WallpaperManager

    var body: some View {
        Form {
            // Per-Space Wallpapers
            Section("Virtual Desktops (Spaces)") {
                Toggle("Different wallpaper per Space", isOn: $spaceManager.isEnabled)
                    .onChange(of: spaceManager.isEnabled) { enabled in
                        if enabled { spaceManager.start() } else { spaceManager.stop() }
                    }

                if spaceManager.isEnabled {
                    HStack {
                        Image(systemName: "square.stack.3d.up")
                            .foregroundColor(.blue)
                        Text("Current Space: \(spaceManager.currentSpaceIndex)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    ForEach(0..<6, id: \.self) { spaceIndex in
                        HStack {
                            Image(systemName: "\(spaceIndex + 1).circle.fill")
                                .foregroundColor(spaceIndex == spaceManager.currentSpaceIndex ? .accentColor : .secondary)
                                .frame(width: 24)

                            Text("Space \(spaceIndex + 1)")
                                .frame(width: 60, alignment: .leading)

                            if let wp = spaceManager.wallpaper(forSpace: spaceIndex) {
                                AsyncThumbnailView(wallpaper: wp, size: CGSize(width: 40, height: 24))
                                    .cornerRadius(3)
                                Text(wp.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 120)
                            } else {
                                Text("Not set")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Menu {
                                ForEach(wallpaperManager.wallpapers) { wallpaper in
                                    Button(wallpaper.name) {
                                        spaceManager.setWallpaper(wallpaper, forSpace: spaceIndex)
                                    }
                                }
                                Divider()
                                Button("Clear") {
                                    spaceManager.clearAssignment(forSpace: spaceIndex)
                                }
                            } label: {
                                Text("Choose")
                                    .font(.caption)
                            }
                            .frame(width: 70)
                        }
                    }

                    Text("Switch between Spaces (Mission Control) to see different wallpapers on each desktop.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Lock Screen
            Section("Lock Screen") {
                Toggle("Show video wallpaper on lock screen", isOn: $lockManager.isEnabled)

                if lockManager.isEnabled {
                    Picker("Video Source", selection: $lockManager.useCurrentWallpaper) {
                        Text("Use current wallpaper").tag(true)
                        Text("Choose specific wallpaper").tag(false)
                    }

                    if !lockManager.useCurrentWallpaper {
                        Menu {
                            ForEach(wallpaperManager.wallpapers) { wallpaper in
                                Button(wallpaper.name) {
                                    lockManager.setLockScreenWallpaper(wallpaper)
                                }
                            }
                        } label: {
                            HStack {
                                if !lockManager.wallpaperPath.isEmpty,
                                   let wp = wallpaperManager.wallpapers.first(where: { $0.url.path == lockManager.wallpaperPath }) {
                                    AsyncThumbnailView(wallpaper: wp, size: CGSize(width: 48, height: 27))
                                        .cornerRadius(4)
                                    Text(wp.name)
                                        .font(.caption)
                                } else {
                                    Text("Select wallpaper...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    Toggle("Show clock overlay", isOn: $lockManager.showClock)

                    Text("Video wallpaper will appear when you lock your Mac. Press any key or click to dismiss.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
