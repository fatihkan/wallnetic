import Foundation
import Combine

/// Desktop clock preferences (#311). Off by default. Kept out of
/// `WallpaperEffectsManager`, so Reset All Effects leaves them alone.
final class DesktopClockSettings: ObservableObject {
    static let shared = DesktopClockSettings()
    static let storageKey = "desktopClock.v1"

    enum Position: String, Codable, CaseIterable, Identifiable {
        case topLeading, topCenter, center, bottomLeading, bottomCenter, bottomTrailing

        var id: String { rawValue }
        var title: String {
            switch self {
            case .topLeading: return String(localized: "Top Left")
            case .topCenter: return String(localized: "Top Center")
            case .center: return String(localized: "Center")
            case .bottomLeading: return String(localized: "Bottom Left")
            case .bottomCenter: return String(localized: "Bottom Center")
            case .bottomTrailing: return String(localized: "Bottom Right")
            }
        }
    }

    enum Size: String, Codable, CaseIterable, Identifiable {
        case small, medium, large

        var id: String { rawValue }
        var title: String {
            switch self {
            case .small: return String(localized: "Small")
            case .medium: return String(localized: "Medium")
            case .large: return String(localized: "Large")
            }
        }
        /// Time text size as a share of the display's visible height.
        var timeFraction: Double {
            switch self {
            case .small: return 0.06
            case .medium: return 0.09
            case .large: return 0.13
            }
        }
    }

    /// The default position avoids the right edge, where Finder places desktop
    /// icons, and the left edge, where Stage Manager shows its strip.
    struct Preferences: Codable, Equatable {
        var showClock = false
        var showDate = true
        var position: Position = .topCenter
        var size: Size = .medium
    }

    @Published private(set) var preferences: Preferences
    private let defaults: UserDefaults

    /// Missing or unreadable preferences fall back to the defaults.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
    }

    func update(_ change: (inout Preferences) -> Void) {
        var next = preferences
        change(&next)
        guard next != preferences, let data = try? JSONEncoder().encode(next) else { return }
        defaults.set(data, forKey: Self.storageKey)
        preferences = next
    }
}
