import Foundation

/// Read-only view onto the wallpaper library (#166 follow-up).
///
/// View-models and services that **only need to query** the library
/// should accept this protocol instead of `WallpaperManager.shared`.
/// Easier to mock in tests and explicit about what's actually needed.
///
/// `WallpaperManager` conforms — see the extension in this file.
/// Migration of the existing 71 `.shared` call sites is incremental and
/// tracked separately; new code should prefer this protocol from day one.
protocol WallpaperReading: AnyObject {
    var wallpapers: [Wallpaper] { get }
    var currentWallpaper: Wallpaper? { get }
    var isPlaying: Bool { get }

    func wallpaper(for screen: NSScreen) -> Wallpaper?
}

/// Mutating surface — for VMs/services that change library state.
///
/// Same migration story as `WallpaperReading`. New code that imports,
/// favorites, or removes wallpapers should declare a dependency on this
/// protocol so it can be unit-tested without touching the real library.
protocol WallpaperWriting: AnyObject {
    func setWallpaper(_ wallpaper: Wallpaper)
    func setWallpaper(_ wallpaper: Wallpaper, for screen: NSScreen)
    func togglePlayback()
    func cycleToNextWallpaper()
    func importVideo(from sourceURL: URL) async throws -> Wallpaper
}

import AppKit

extension WallpaperManager: WallpaperReading, WallpaperWriting {}
