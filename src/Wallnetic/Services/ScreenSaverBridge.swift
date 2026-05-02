import Foundation
import AppKit
import SwiftUI

/// Bridge between Wallnetic and macOS Screen Saver system
/// Exports wallpaper info for a companion .saver bundle to use
class ScreenSaverBridge {
    static let shared = ScreenSaverBridge()

    @AppStorage("screensaver.enabled") var isEnabled: Bool = false
    @AppStorage("screensaver.useCurrentWallpaper") var useCurrentWallpaper: Bool = true
    @AppStorage("screensaver.useRandom") var useRandom: Bool = false
    @AppStorage("screensaver.showClock") var showClock: Bool = true

    private let sharedDefaultsSuite = "com.wallnetic.screensaver"

    private init() {}

    /// Syncs current wallpaper info to shared defaults for screen saver to read
    func syncToScreenSaver() {
        guard isEnabled else { return }

        let defaults = UserDefaults(suiteName: sharedDefaultsSuite)

        if useCurrentWallpaper, let current = WallpaperManager.shared.currentWallpaper {
            defaults?.set(current.url.path, forKey: "wallpaperPath")
            defaults?.set(current.name, forKey: "wallpaperName")
        } else if useRandom {
            let wallpapers = WallpaperManager.shared.wallpapers
            if let random = wallpapers.randomElement() {
                defaults?.set(random.url.path, forKey: "wallpaperPath")
                defaults?.set(random.name, forKey: "wallpaperName")
            }
        }

        // Sync library paths for screen saver to browse
        let paths = WallpaperManager.shared.wallpapers.map { $0.url.path }
        defaults?.set(paths, forKey: "libraryPaths")
        defaults?.set(showClock, forKey: "showClock")
        defaults?.synchronize()

        Log.screenSaver.info("Synced wallpaper info to screen saver defaults")
    }

    /// Returns the path to install a .saver bundle
    var screenSaverInstallPath: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Screen Savers")
    }
}
