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

    private let defaults = UserDefaults.standard
    private let appearanceKey = "appearanceMode"

    private init() {
        // Load saved appearance
        if let savedMode = defaults.string(forKey: appearanceKey),
           let mode = AppearanceMode(rawValue: savedMode) {
            appearanceMode = mode
        } else {
            appearanceMode = .system
        }

        applyAppearance()
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
