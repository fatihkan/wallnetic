import SwiftUI

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
                        AsyncThumbnailView(wallpaper: wallpaper, size: CGSize(width: 48, height: 27))
                            .cornerRadius(4)
                        Text(wallpaper.displayName)
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
            HStack {
                VStack(alignment: .leading) {
                    Text("Select Wallpaper").font(.headline)
                    Text("for \(screen.localizedName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()
            .background(.bar)

            Divider()

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
                        .overlay { ProgressView() }
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
            Text(wallpaper.displayName)
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
    @AppStorage("selectedVideoModel") private var selectedModelRaw: String = VideoModel.klingStandard.rawValue
    @State private var apiKey: String = ""
    @State private var isValidating = false
    @State private var validationStatus: ValidationStatus = .notValidated
    @State private var showingAPIKey = false

    private let apiProvider = APIProvider.falai

    private var selectedModel: VideoModel {
        get { VideoModel(rawValue: selectedModelRaw) ?? .klingStandard }
        set { selectedModelRaw = newValue.rawValue }
    }

    enum ValidationStatus {
        case notValidated, validating, valid, invalid(String)

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
            Section("fal.ai API Key") {
                HStack {
                    if showingAPIKey {
                        TextField(apiProvider.apiKeyPlaceholder, text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField(apiProvider.apiKeyPlaceholder, text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button { showingAPIKey.toggle() } label: {
                        Image(systemName: showingAPIKey ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }

                HStack {
                    Image(systemName: validationStatus.icon)
                        .foregroundColor(validationStatus.color)
                    Text(validationStatus.message)
                        .foregroundColor(validationStatus.color)
                        .font(.caption)
                    Spacer()
                    if case .validating = validationStatus {
                        ProgressView().scaleEffect(0.7)
                    }
                }

                HStack {
                    Button("Validate & Save") { validateAndSaveAPIKey() }
                        .disabled(apiKey.isEmpty || isValidating)
                    Button("Clear") { clearAPIKey() }
                        .disabled(apiKey.isEmpty)
                    Spacer()
                    Link("Get API Key", destination: apiProvider.signupURL)
                        .font(.caption)
                }
            }

            Section("Default Video Model") {
                ForEach(VideoModel.allCases, id: \.self) { model in
                    HStack {
                        Image(systemName: model.icon)
                            .foregroundColor(model.isAnimeOptimized ? .pink : .blue)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(model.displayName)
                                if model.isAnimeOptimized {
                                    Text("ANIME").font(.caption2)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Color.pink.opacity(0.2)).cornerRadius(3)
                                }
                            }
                            Text(model.description).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("$\(String(format: "%.2f", model.costPerSecond))/s").font(.caption).foregroundColor(.secondary)
                            Text("≤\(model.maxDuration)s").font(.caption2).foregroundColor(.secondary)
                        }
                        if selectedModel == model {
                            Image(systemName: "checkmark").foregroundColor(.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedModelRaw = model.rawValue }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadAPIKey() }
    }

    private func loadAPIKey() {
        if let key = KeychainManager.shared.getAPIKey(for: apiProvider) {
            apiKey = key; validationStatus = .valid
        }
    }

    private func validateAndSaveAPIKey() {
        guard !apiKey.isEmpty else { return }
        isValidating = true; validationStatus = .validating
        Task {
            do {
                let isValid = try await AIService.shared.validateAPIKey(apiKey)
                await MainActor.run {
                    isValidating = false
                    if isValid { KeychainManager.shared.saveAPIKey(apiKey, for: apiProvider); validationStatus = .valid }
                    else { validationStatus = .invalid("Invalid API key") }
                }
            } catch {
                await MainActor.run { isValidating = false; validationStatus = .invalid(error.localizedDescription) }
            }
        }
    }

    private func clearAPIKey() {
        apiKey = ""; KeychainManager.shared.deleteAPIKey(for: apiProvider); validationStatus = .notValidated
    }
}
