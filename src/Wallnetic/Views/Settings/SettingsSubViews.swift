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
    @AppStorage("nowPlayingOverlay.enabled") private var nowPlayingEnabled = false
    @AppStorage("audioVisualizer.overlayEnabled") private var audioVisualizerEnabled = false

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
            Section("Desktop Overlays") {
                Toggle("Audio visualizer", isOn: $audioVisualizerEnabled)
                    .onChange(of: audioVisualizerEnabled) { newValue in
                        if newValue { AudioVisualizerOverlayController.shared.show() }
                        else { AudioVisualizerOverlayController.shared.hide() }
                    }
                    .help("Frequency bars driven by system audio or the microphone")
                if audioVisualizerEnabled {
                    AudioVisualizerSourcePicker()
                }
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
                    let url = applicationSupportURL().appendingPathComponent("Wallnetic/Library")
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
            Log.app.error("Failed to set launch at login: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private struct AudioVisualizerSourcePicker: View {
    @ObservedObject private var manager = AudioVisualizerManager.shared
    @State private var source: AudioVisualizerManager.Source = .system
    @State private var style: AudioVisualizerManager.Style = .bars
    @State private var position: AudioVisualizerManager.Position = .bottomRight
    @State private var sizePreset: AudioVisualizerManager.Size = .medium

    var body: some View {
        Picker("Audio source", selection: $source) {
            ForEach(AudioVisualizerManager.Source.allCases) { s in
                Text(s.label).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .onAppear {
            source = manager.source
            style = manager.style
            position = manager.position
            sizePreset = manager.sizePreset
        }
        .onChange(of: source) { newValue in manager.source = newValue }

        // #159 — sensitivity slider
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Sensitivity")
                Spacer()
                Text(String(format: "%.1fx", manager.sensitivity))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $manager.sensitivity, in: 0.3...3.0, step: 0.1)
        }

        // #160 — visual style
        Picker("Style", selection: $style) {
            ForEach(AudioVisualizerManager.Style.allCases) { s in
                Text(s.label).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: style) { newValue in manager.style = newValue }

        // #162 — size preset
        Picker("Size", selection: $sizePreset) {
            ForEach(AudioVisualizerManager.Size.allCases) { s in
                Text(s.label).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: sizePreset) { newValue in manager.sizePreset = newValue }

        // #161 — corner anchor
        Picker("Position", selection: $position) {
            ForEach(AudioVisualizerManager.Position.allCases) { p in
                Text(p.label).tag(p)
            }
        }
        .onChange(of: position) { newValue in manager.position = newValue }

        if let error = manager.lastError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.orange)
        } else if manager.permissionDenied {
            Label(
                "Permission denied. Enable Screen Recording (for system audio) or Microphone access in System Settings.",
                systemImage: "lock.fill"
            )
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }
}

// MARK: - Playback Settings

struct PlaybackSettingsView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @AppStorage(BatteryPromptService.alwaysPlayKey) private var alwaysPlayOnBattery: Bool = false

    var body: some View {
        Form {
            Section("Power Management") {
                Toggle("Pause when on battery power", isOn: $wallpaperManager.pauseOnBattery)
                    .help("When enabled, Wallnetic asks before pausing (or pauses silently if you opted out of the prompt).")
                Toggle("Always play on battery (skip prompt)", isOn: $alwaysPlayOnBattery)
                    .disabled(!wallpaperManager.pauseOnBattery)
                    .help("Overrides the pause: the live wallpaper keeps playing on battery without asking.")
                Toggle("Pause when fullscreen app is active", isOn: $wallpaperManager.pauseOnFullscreen)
                Toggle("Auto-resume when conditions change", isOn: $wallpaperManager.shouldAutoResume)
                Button("Reset battery prompt") {
                    BatteryPromptService.shared.resetPreferences()
                    alwaysPlayOnBattery = false
                }
                .help("Clears saved battery-mode choice so the prompt appears again.")
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
