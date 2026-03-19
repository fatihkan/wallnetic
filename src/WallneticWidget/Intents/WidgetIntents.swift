import AppIntents
import WidgetKit

// MARK: - Play/Pause Intent

@available(macOS 14.0, *)
struct PlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Playback"
    static var description = IntentDescription("Play or pause the current wallpaper")

    func perform() async throws -> some IntentResult {
        // Write the action to shared UserDefaults for the main app to handle
        let defaults = UserDefaults(suiteName: "group.com.wallnetic.shared")
        let currentState = defaults?.bool(forKey: "isPlaying") ?? false
        defaults?.set(!currentState, forKey: "isPlaying")
        defaults?.set("playPause", forKey: "pendingAction")
        defaults?.set(Date(), forKey: "actionTimestamp")

        // Reload widget to reflect new state
        WidgetCenter.shared.reloadAllTimelines()

        return .result()
    }
}

// MARK: - Set Wallpaper Intent

@available(macOS 14.0, *)
struct SetWallpaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Wallpaper"
    static var description = IntentDescription("Set a specific wallpaper")

    @Parameter(title: "Wallpaper ID")
    var wallpaperID: String

    init() {
        self.wallpaperID = ""
    }

    init(wallpaperID: String) {
        self.wallpaperID = wallpaperID
    }

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.com.wallnetic.shared")
        defaults?.set("setWallpaper", forKey: "pendingAction")
        defaults?.set(wallpaperID, forKey: "pendingWallpaperID")
        defaults?.set(Date(), forKey: "actionTimestamp")

        // Reload widget
        WidgetCenter.shared.reloadAllTimelines()

        return .result()
    }
}

// MARK: - Next Wallpaper Intent

@available(macOS 14.0, *)
struct NextWallpaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Wallpaper"
    static var description = IntentDescription("Switch to the next wallpaper")

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.com.wallnetic.shared")
        defaults?.set("nextWallpaper", forKey: "pendingAction")
        defaults?.set(Date(), forKey: "actionTimestamp")

        // Reload widget
        WidgetCenter.shared.reloadAllTimelines()

        return .result()
    }
}
