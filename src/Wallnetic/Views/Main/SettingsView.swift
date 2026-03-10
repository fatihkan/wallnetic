import SwiftUI
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            PlaybackSettingsView()
                .tabItem {
                    Label("Playback", systemImage: "play.circle")
                }

            DisplaySettingsView()
                .tabItem {
                    Label("Display", systemImage: "display")
                }

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var launchAtLoginEnabled = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLoginEnabled)
                    .onChange(of: launchAtLoginEnabled) { newValue in
                        setLaunchAtLogin(enabled: newValue)
                    }

                Toggle("Show in menu bar", isOn: .constant(true))
                    .disabled(true)
                    .help("Menu bar icon is always shown")
            }

            Section("Library") {
                LabeledContent("Location") {
                    Text("~/Library/Application Support/Wallnetic")
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }

                LabeledContent("Wallpapers") {
                    Text("\(wallpaperManager.wallpapers.count)")
                }

                Button("Open in Finder") {
                    let url = FileManager.default.urls(
                        for: .applicationSupportDirectory,
                        in: .userDomainMask
                    ).first!.appendingPathComponent("Wallnetic/Library")
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to set launch at login: \(error)")
        }
    }
}

// MARK: - Playback Settings

struct PlaybackSettingsView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager

    var body: some View {
        Form {
            Section("Power Management") {
                Toggle("Pause when on battery power", isOn: $wallpaperManager.pauseOnBattery)

                Toggle("Pause when fullscreen app is active", isOn: $wallpaperManager.pauseOnFullscreen)

                Toggle("Auto-resume when conditions change", isOn: $wallpaperManager.shouldAutoResume)
            }

            Section("Performance") {
                Picker("Video Quality", selection: .constant("High")) {
                    Text("Low").tag("Low")
                    Text("Medium").tag("Medium")
                    Text("High").tag("High")
                }

                Text("Higher quality uses more system resources")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Display Settings

struct DisplaySettingsView: View {
    @State private var screens = NSScreen.screens

    var body: some View {
        Form {
            Section("Connected Displays") {
                ForEach(screens, id: \.self) { screen in
                    HStack {
                        Image(systemName: "display")
                        VStack(alignment: .leading) {
                            Text(screen.localizedName)
                            Text("\(Int(screen.frame.width))×\(Int(screen.frame.height))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if screen == NSScreen.main {
                            Text("Main")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                }
            }

            Section("Options") {
                Picker("Wallpaper Mode", selection: .constant("same")) {
                    Text("Same on all displays").tag("same")
                    Text("Different per display").tag("different")
                }

                Picker("Scaling", selection: .constant("fill")) {
                    Text("Fill").tag("fill")
                    Text("Fit").tag("fit")
                    Text("Stretch").tag("stretch")
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
        }
    }
}

// MARK: - About Settings

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Wallnetic")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 1.0.0 (Build 1)")
                .foregroundColor(.secondary)

            Text("AI-Powered Live Wallpapers for macOS")
                .font(.subheadline)

            Divider()

            HStack(spacing: 20) {
                Link("Website", destination: URL(string: "https://wallnetic.app")!)
                Link("GitHub", destination: URL(string: "https://github.com/fatihkan/wallnetic")!)
                Link("Support", destination: URL(string: "mailto:support@wallnetic.app")!)
            }
            .font(.caption)

            Spacer()

            Text("© 2026 Wallnetic. All rights reserved.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
        .environmentObject(WallpaperManager.shared)
}
