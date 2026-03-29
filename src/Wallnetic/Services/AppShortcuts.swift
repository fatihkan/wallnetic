import AppIntents
import Foundation

// MARK: - Set Wallpaper Intent

@available(macOS 14.0, *)
struct SetWallpaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Wallpaper"
    static var description = IntentDescription("Set a specific wallpaper by name")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Wallpaper Name")
    var wallpaperName: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let wallpapers = await MainActor.run { WallpaperManager.shared.wallpapers }

        guard let wallpaper = wallpapers.first(where: {
            $0.name.localizedCaseInsensitiveContains(wallpaperName)
        }) else {
            throw ShortcutError.wallpaperNotFound(wallpaperName)
        }

        await MainActor.run {
            WallpaperManager.shared.setWallpaper(wallpaper)
        }

        return .result(value: "Set wallpaper to \(wallpaper.name)")
    }
}

// MARK: - Next Wallpaper Intent

@available(macOS 14.0, *)
struct NextWallpaperShortcutIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Wallpaper"
    static var description = IntentDescription("Switch to the next wallpaper in the library")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        await MainActor.run {
            WallpaperManager.shared.cycleToNextWallpaper()
        }

        let name = await MainActor.run {
            WallpaperManager.shared.currentWallpaper?.name ?? "Unknown"
        }

        return .result(value: "Switched to \(name)")
    }
}

// MARK: - Toggle Playback Intent

@available(macOS 14.0, *)
struct TogglePlaybackIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Wallpaper Playback"
    static var description = IntentDescription("Play or pause the live wallpaper")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let isPlaying = await MainActor.run {
            WallpaperManager.shared.togglePlayback()
            return WallpaperManager.shared.isPlaying
        }

        return .result(value: isPlaying ? "Playing" : "Paused")
    }
}

// MARK: - Random Wallpaper Intent

@available(macOS 14.0, *)
struct RandomWallpaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Random Wallpaper"
    static var description = IntentDescription("Set a random wallpaper from your library or favorites")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "From Favorites Only", default: false)
    var favoritesOnly: Bool

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let wallpapers = await MainActor.run {
            favoritesOnly
                ? WallpaperManager.shared.wallpapers.filter { $0.isFavorite }
                : WallpaperManager.shared.wallpapers
        }

        guard let random = wallpapers.randomElement() else {
            throw ShortcutError.noWallpapers
        }

        await MainActor.run {
            WallpaperManager.shared.setWallpaper(random)
        }

        return .result(value: "Set random wallpaper: \(random.name)")
    }
}

// MARK: - Get Current Wallpaper Intent

@available(macOS 14.0, *)
struct GetCurrentWallpaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Current Wallpaper"
    static var description = IntentDescription("Get the name of the current wallpaper")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let name = await MainActor.run {
            WallpaperManager.shared.currentWallpaper?.name ?? "None"
        }
        return .result(value: name)
    }
}

// MARK: - App Shortcuts Provider

@available(macOS 14.0, *)
struct WallneticShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextWallpaperShortcutIntent(),
            phrases: [
                "Next wallpaper in \(.applicationName)",
                "Change wallpaper in \(.applicationName)",
                "Switch wallpaper in \(.applicationName)"
            ],
            shortTitle: "Next Wallpaper",
            systemImageName: "forward.fill"
        )

        AppShortcut(
            intent: TogglePlaybackIntent(),
            phrases: [
                "Pause wallpaper in \(.applicationName)",
                "Play wallpaper in \(.applicationName)",
                "Toggle \(.applicationName)"
            ],
            shortTitle: "Toggle Playback",
            systemImageName: "playpause.fill"
        )

        AppShortcut(
            intent: RandomWallpaperIntent(),
            phrases: [
                "Random wallpaper in \(.applicationName)",
                "Surprise me with \(.applicationName)"
            ],
            shortTitle: "Random Wallpaper",
            systemImageName: "shuffle"
        )
    }
}

// MARK: - Errors

enum ShortcutError: LocalizedError {
    case wallpaperNotFound(String)
    case noWallpapers

    var errorDescription: String? {
        switch self {
        case .wallpaperNotFound(let name): return "No wallpaper found matching '\(name)'"
        case .noWallpapers: return "No wallpapers in library"
        }
    }
}
