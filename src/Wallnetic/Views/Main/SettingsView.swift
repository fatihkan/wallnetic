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
        .frame(width: 500, height: 380)
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

// MARK: - Display Settings

struct DisplaySettingsView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var screens = NSScreen.screens
    @State private var selectedScreen: NSScreen?
    @State private var showingWallpaperPicker = false

    var body: some View {
        Form {
            Section("Connected Displays") {
                ForEach(screens, id: \.self) { screen in
                    ScreenRow(
                        screen: screen,
                        wallpaper: wallpaperManager.wallpaper(for: screen),
                        isSelected: selectedScreen == screen,
                        showDifferentMode: wallpaperManager.wallpaperMode == .different
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if wallpaperManager.wallpaperMode == .different {
                            selectedScreen = screen
                            showingWallpaperPicker = true
                        }
                    }
                }
            }

            Section("Options") {
                Picker("Wallpaper Mode", selection: $wallpaperManager.wallpaperMode) {
                    ForEach(WallpaperMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .onChange(of: wallpaperManager.wallpaperMode) { newMode in
                    wallpaperManager.setWallpaperMode(newMode)
                }

                if wallpaperManager.wallpaperMode == .different {
                    Text("Click on a display above to set its wallpaper")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
        }
        .sheet(isPresented: $showingWallpaperPicker) {
            if let screen = selectedScreen {
                ScreenWallpaperPickerView(screen: screen)
                    .environmentObject(wallpaperManager)
            }
        }
    }
}

// MARK: - Screen Row

struct ScreenRow: View {
    let screen: NSScreen
    let wallpaper: Wallpaper?
    let isSelected: Bool
    let showDifferentMode: Bool

    var body: some View {
        HStack {
            Image(systemName: "display")
                .font(.title2)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(screen.localizedName)
                        .fontWeight(.medium)

                    if screen == NSScreen.main {
                        Text("Main")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .cornerRadius(4)
                    }
                }

                Text("\(Int(screen.frame.width))×\(Int(screen.frame.height))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if showDifferentMode {
                if let wallpaper = wallpaper {
                    HStack(spacing: 8) {
                        AsyncThumbnailView(
                            wallpaper: wallpaper,
                            size: CGSize(width: 48, height: 27)
                        )
                        .cornerRadius(4)

                        Text(wallpaper.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: 100)
                    }
                } else {
                    Text("Not set")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Screen Wallpaper Picker

struct ScreenWallpaperPickerView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @Environment(\.dismiss) var dismiss
    let screen: NSScreen

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Select Wallpaper")
                        .font(.headline)
                    Text("for \(screen.localizedName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding()
            .background(.bar)

            Divider()

            // Wallpaper Grid
            if wallpaperManager.wallpapers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No wallpapers in library")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(wallpaperManager.wallpapers) { wallpaper in
                            WallpaperPickerCard(
                                wallpaper: wallpaper,
                                isSelected: wallpaperManager.screenWallpapers[screen.localizedName] == wallpaper.id
                            )
                            .onTapGesture {
                                wallpaperManager.setWallpaper(wallpaper, for: screen)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - Wallpaper Picker Card

struct WallpaperPickerCard: View {
    let wallpaper: Wallpaper
    let isSelected: Bool
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .aspectRatio(16/9, contentMode: .fit)
                        .overlay {
                            ProgressView()
                        }
                }

                if isSelected {
                    Color.accentColor.opacity(0.3)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }
            }
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )

            Text(wallpaper.name)
                .font(.caption)
                .lineLimit(1)
        }
        .task {
            thumbnail = await wallpaper.generateThumbnail(size: CGSize(width: 200, height: 112))
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
