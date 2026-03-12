import SwiftUI
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            PlaybackSettingsView()
                .tabItem {
                    Label("Playback", systemImage: "play.circle")
                }

            DisplaySettingsView()
                .tabItem {
                    Label("Display", systemImage: "display")
                }

            AISettingsView()
                .tabItem {
                    Label("AI", systemImage: "wand.and.stars")
                }

            NotificationSettingsView()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 480)
    }
}

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
        .onAppear {
            notificationManager.checkAuthorization()
        }
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        Form {
            Section("Theme") {
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
                    .onTapGesture {
                        themeManager.appearanceMode = mode
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func descriptionFor(_ mode: AppearanceMode) -> String {
        switch mode {
        case .system:
            return "Follow system appearance"
        case .light:
            return "Always use light mode"
        case .dark:
            return "Always use dark mode"
        }
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

// MARK: - AI Settings

struct AISettingsView: View {
    @AppStorage("aiProvider") private var aiProviderRaw: String = AIProvider.replicate.rawValue
    @State private var apiKey: String = ""
    @State private var isValidating = false
    @State private var validationStatus: ValidationStatus = .notValidated
    @State private var showingAPIKey = false

    private var aiProvider: AIProvider {
        get { AIProvider(rawValue: aiProviderRaw) ?? .replicate }
        set { aiProviderRaw = newValue.rawValue }
    }

    enum ValidationStatus {
        case notValidated
        case validating
        case valid
        case invalid(String)

        var color: Color {
            switch self {
            case .notValidated: return .secondary
            case .validating: return .orange
            case .valid: return .green
            case .invalid: return .red
            }
        }

        var icon: String {
            switch self {
            case .notValidated: return "questionmark.circle"
            case .validating: return "arrow.clockwise"
            case .valid: return "checkmark.circle.fill"
            case .invalid: return "xmark.circle.fill"
            }
        }

        var message: String {
            switch self {
            case .notValidated: return "Not validated"
            case .validating: return "Validating..."
            case .valid: return "Connected"
            case .invalid(let error): return error
            }
        }
    }

    var body: some View {
        Form {
            Section("AI Provider") {
                Picker("Provider", selection: Binding(
                    get: { aiProvider },
                    set: { newValue in
                        aiProviderRaw = newValue.rawValue
                        // Clear key when switching providers
                        apiKey = ""
                        validationStatus = .notValidated
                        loadAPIKey()
                    }
                )) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)

                Text(aiProvider == .replicate
                    ? "Replicate offers Stable Diffusion, FLUX, and more models"
                    : "fal.ai provides fast inference with FLUX models")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("API Key") {
                HStack {
                    if showingAPIKey {
                        TextField(aiProvider.apiKeyPlaceholder, text: $apiKey)
                            .textFieldStyle(.plain)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField(aiProvider.apiKeyPlaceholder, text: $apiKey)
                            .textFieldStyle(.plain)
                    }

                    Button {
                        showingAPIKey.toggle()
                    } label: {
                        Image(systemName: showingAPIKey ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Image(systemName: validationStatus.icon)
                        .foregroundColor(validationStatus.color)

                    Text(validationStatus.message)
                        .foregroundColor(validationStatus.color)
                        .font(.caption)

                    Spacer()

                    if case .validating = validationStatus {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }

                HStack {
                    Button("Validate & Save") {
                        validateAndSaveAPIKey()
                    }
                    .disabled(apiKey.isEmpty || isValidating)

                    Button("Clear") {
                        clearAPIKey()
                    }
                    .disabled(apiKey.isEmpty)

                    Spacer()

                    Link("Get API Key", destination: aiProvider.signupURL)
                        .font(.caption)
                }
            }

            Section("Usage Info") {
                if case .valid = validationStatus {
                    LabeledContent("Provider") {
                        Text(aiProvider.displayName)
                    }

                    LabeledContent("Status") {
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Ready")
                        }
                    }
                } else {
                    Text("Enter your API key above to enable AI wallpaper generation.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("You can get a free API key from \(aiProvider.displayName)'s website.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadAPIKey()
        }
    }

    private func loadAPIKey() {
        if let key = KeychainManager.shared.getAPIKey(for: aiProvider) {
            apiKey = key
            validationStatus = .valid
        } else {
            apiKey = ""
            validationStatus = .notValidated
        }
    }

    private func validateAndSaveAPIKey() {
        guard !apiKey.isEmpty else { return }

        isValidating = true
        validationStatus = .validating

        Task {
            do {
                let isValid = try await AIService.shared.validateAPIKey(apiKey, provider: aiProvider)

                await MainActor.run {
                    isValidating = false
                    if isValid {
                        KeychainManager.shared.saveAPIKey(apiKey, for: aiProvider)
                        validationStatus = .valid
                    } else {
                        validationStatus = .invalid("Invalid API key")
                    }
                }
            } catch {
                await MainActor.run {
                    isValidating = false
                    validationStatus = .invalid(error.localizedDescription)
                }
            }
        }
    }

    private func clearAPIKey() {
        apiKey = ""
        KeychainManager.shared.deleteAPIKey(for: aiProvider)
        validationStatus = .notValidated
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
