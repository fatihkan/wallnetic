import Foundation
import os.log

/// Resolves Application Support directory or aborts. macOS guarantees the
/// directory exists for any signed app — `fatalError` here just makes the
/// invariant loud instead of a silent force-unwrap.
func applicationSupportURL() -> URL {
    if let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
        return url
    }
    fatalError("Application Support directory unavailable — environment is unusable.")
}

/// Centralized `os.log` Logger registry. Replaces ad-hoc `print`/`NSLog`
/// calls throughout the app so log output is filterable in Console.app
/// (`subsystem == "com.wallnetic.app"`) and `.debug` entries are stripped
/// from Release builds automatically by the OSLog system.
///
/// Usage:
///     Log.power.info("Switched to battery power")
///     Log.auth.error("Sign in failed: \(error.localizedDescription, privacy: .public)")
///     Log.video.debug("Frame decoded — pts=\(pts)")          // Release: hidden
enum Log {
    private static let subsystem = "com.wallnetic.app"

    static let app          = Logger(subsystem: subsystem, category: "App")
    static let ai           = Logger(subsystem: subsystem, category: "AI")
    static let browser      = Logger(subsystem: subsystem, category: "Browser")
    static let analytics    = Logger(subsystem: subsystem, category: "Analytics")
    static let auth         = Logger(subsystem: subsystem, category: "Auth")
    static let cloud        = Logger(subsystem: subsystem, category: "Cloud")
    static let deepLink     = Logger(subsystem: subsystem, category: "DeepLink")
    static let download     = Logger(subsystem: subsystem, category: "Download")
    static let history      = Logger(subsystem: subsystem, category: "GenerationHistory")
    static let icloud       = Logger(subsystem: subsystem, category: "iCloud")
    static let keychain     = Logger(subsystem: subsystem, category: "Keychain")
    static let lockScreen   = Logger(subsystem: subsystem, category: "LockScreen")
    static let mlw          = Logger(subsystem: subsystem, category: "MLWDecryptor")
    static let music        = Logger(subsystem: subsystem, category: "MusicReactive")
    static let notification = Logger(subsystem: subsystem, category: "Notification")
    static let photos       = Logger(subsystem: subsystem, category: "Photos")
    static let slideshow    = Logger(subsystem: subsystem, category: "Slideshow")
    static let power        = Logger(subsystem: subsystem, category: "Power")
    static let render       = Logger(subsystem: subsystem, category: "Render")
    static let scheduler    = Logger(subsystem: subsystem, category: "Scheduler")
    static let screenSaver  = Logger(subsystem: subsystem, category: "ScreenSaver")
    static let shared       = Logger(subsystem: subsystem, category: "SharedData")
    static let space        = Logger(subsystem: subsystem, category: "SpaceWallpaper")
    static let store        = Logger(subsystem: subsystem, category: "WallpaperStore")
    static let supabase     = Logger(subsystem: subsystem, category: "Supabase")
    static let thumbnail    = Logger(subsystem: subsystem, category: "Thumbnail")
    static let timeOfDay    = Logger(subsystem: subsystem, category: "TimeOfDay")
    static let update       = Logger(subsystem: subsystem, category: "UpdateChecker")
    static let usage        = Logger(subsystem: subsystem, category: "Usage")
    static let video        = Logger(subsystem: subsystem, category: "Video")
    static let visualizer   = Logger(subsystem: subsystem, category: "AudioVisualizer")
    static let weather      = Logger(subsystem: subsystem, category: "Weather")
    static let ui           = Logger(subsystem: subsystem, category: "UI")
    static let window       = Logger(subsystem: subsystem, category: "Window")
}
