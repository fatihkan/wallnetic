import SwiftUI

/// App appearance mode
enum AppearanceMode: String, CaseIterable, Codable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

/// Manager for app theme/appearance settings
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var appearanceMode: AppearanceMode {
        didSet {
            saveAppearance()
            applyAppearance()
        }
    }

    /// Dynamic accent color derived from current wallpaper
    @Published var accentColor: Color = .accentColor
    @AppStorage("dynamicThemeEnabled") var dynamicThemeEnabled: Bool = false

    private let defaults = UserDefaults.standard
    private let appearanceKey = "appearanceMode"
    private var wallpaperObserver: Any?

    private init() {
        // Load saved appearance
        if let savedMode = defaults.string(forKey: appearanceKey),
           let mode = AppearanceMode(rawValue: savedMode) {
            appearanceMode = mode
        } else {
            appearanceMode = .system
        }

        applyAppearance()
        observeWallpaperChanges()
    }

    // MARK: - Dynamic Theme

    private func observeWallpaperChanges() {
        wallpaperObserver = NotificationCenter.default.addObserver(
            forName: .wallpaperDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, self.dynamicThemeEnabled else { return }
            if let wallpaper = notification.object as? Wallpaper,
               let hex = wallpaper.dominantColorHex,
               let nsColor = NSColor(hex: hex) {
                self.accentColor = Color(nsColor: nsColor)
            }
        }
    }

    /// Update accent color from current wallpaper
    func updateAccentFromWallpaper(_ wallpaper: Wallpaper?) {
        guard dynamicThemeEnabled, let wp = wallpaper else {
            accentColor = .accentColor
            return
        }
        if let hex = wp.dominantColorHex, let nsColor = NSColor(hex: hex) {
            accentColor = Color(nsColor: nsColor)
        }

        // Extract if not available yet
        if wp.dominantColorHex == nil {
            Task {
                if let hex = await wp.extractDominantColor() {
                    await MainActor.run {
                        self.accentColor = Color(nsColor: NSColor(hex: hex) ?? .controlAccentColor)
                    }
                }
            }
        }
    }

    // MARK: - Persistence

    private func saveAppearance() {
        defaults.set(appearanceMode.rawValue, forKey: appearanceKey)
    }

    // MARK: - Apply Theme

    func applyAppearance() {
        DispatchQueue.main.async {
            switch self.appearanceMode {
            case .system:
                NSApp.appearance = nil
            case .light:
                NSApp.appearance = NSAppearance(named: .aqua)
            case .dark:
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }
}
