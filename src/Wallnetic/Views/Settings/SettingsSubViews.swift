import SwiftUI
import ServiceManagement

// MARK: - Notification Settings

struct NotificationSettingsView: View {
    @ObservedObject private var notificationManager = NotificationManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Enable Notifications", isOn: $notificationManager.notificationsEnabled)

                if notificationManager.notificationsEnabled && !notificationManager.isAuthorized {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("Notifications are not authorized. Please enable in System Settings.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Open Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }

            if notificationManager.notificationsEnabled {
                Section("Notification Types") {
                    ForEach(NotificationType.allCases, id: \.self) { type in
                        Toggle(isOn: Binding(
                            get: { notificationManager.isEnabled(type) },
                            set: { notificationManager.setEnabled(type, enabled: $0) }
                        )) {
                            HStack {
                                Image(systemName: type.icon)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(type.rawValue)
                                    Text(type.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                Section("Options") {
                    Toggle("Play Sound", isOn: $notificationManager.soundEnabled)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { notificationManager.checkAuthorization() }
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        Form {
            Section("Theme") {
                Toggle("Dynamic accent color from wallpaper", isOn: $themeManager.dynamicThemeEnabled)
                    .help("UI accent color adapts to the current wallpaper's dominant color")

                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    HStack {
                        Image(systemName: mode.icon)
                            .foregroundColor(mode == .dark ? .purple : (mode == .light ? .orange : .accentColor))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.rawValue)
                            Text(descriptionFor(mode))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if themeManager.appearanceMode == mode {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { themeManager.appearanceMode = mode }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func descriptionFor(_ mode: AppearanceMode) -> String {
        switch mode {
        case .system: return "Follow system appearance"
        case .light: return "Always use light mode"
        case .dark: return "Always use dark mode"
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var launchAtLoginEnabled = false
    @AppStorage("hideDockIcon") private var hideDockIcon = false
    @AppStorage("island.enabled") private var islandEnabled = false
    @AppStorage("globalHotkeysEnabled") private var globalHotkeysEnabled = false

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
                Toggle("Hide Dock icon", isOn: $hideDockIcon)
                    .onChange(of: hideDockIcon) { newValue in
                        NSApp.setActivationPolicy(newValue ? .accessory : .regular)
                    }
                    .help("Run only in menu bar without showing in the Dock")
                Toggle("Dynamic Island", isOn: $islandEnabled)
                    .onChange(of: islandEnabled) { newValue in
                        if newValue { DynamicIslandController.shared.show() }
                        else { DynamicIslandController.shared.hide() }
                    }
                    .help("Show wallpaper controls in a floating pill at the top of the screen")
                Toggle("Global Hotkeys", isOn: $globalHotkeysEnabled)
                    .help("⌘⇧→ Next, ⌘⇧← Prev, ⌘⇧P Play/Pause, ⌘⇧R Random (restart required)")
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
                    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                        .appendingPathComponent("Wallnetic/Library")
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLoginEnabled = SMAppService.mainApp.status == .enabled }
    }

    private func setLaunchAtLogin(enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
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
                Toggle("Use Metal Renderer", isOn: $wallpaperManager.useMetalRenderer)
                    .help("Metal provides better GPU acceleration. Restart app after changing.")
                Text("Metal renderer uses GPU for video playback (recommended)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
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
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                .foregroundColor(.secondary)
            Text("Live Video Wallpapers for macOS")
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
