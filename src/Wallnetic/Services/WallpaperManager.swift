import Foundation
import SwiftUI
import Combine

/// Central manager for wallpaper state and settings
class WallpaperManager: ObservableObject {
    static let shared = WallpaperManager()

    // MARK: - Published Properties

    @Published var wallpapers: [Wallpaper] = []
    @Published var currentWallpaper: Wallpaper?
    @Published var isPlaying: Bool = false

    // Settings
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("pauseOnBattery") var pauseOnBattery: Bool = true
    @AppStorage("pauseOnFullscreen") var pauseOnFullscreen: Bool = true
    @AppStorage("shouldAutoResume") var shouldAutoResume: Bool = true

    // MARK: - Properties

    private let fileManager = FileManager.default
    private var libraryURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let wallneticDir = appSupport.appendingPathComponent("Wallnetic/Library", isDirectory: true)

        // Create directory if needed
        if !fileManager.fileExists(atPath: wallneticDir.path) {
            try? fileManager.createDirectory(at: wallneticDir, withIntermediateDirectories: true)
        }

        return wallneticDir
    }

    // MARK: - Initialization

    private init() {
        loadWallpapers()
    }

    // MARK: - Library Management

    /// Loads all wallpapers from the library directory
    func loadWallpapers() {
        wallpapers = []

        guard let contents = try? fileManager.contentsOfDirectory(
            at: libraryURL,
            includingPropertiesForKeys: [.contentTypeKey],
            options: .skipsHiddenFiles
        ) else { return }

        for url in contents {
            if isVideoFile(url) {
                let wallpaper = Wallpaper(url: url)
                wallpapers.append(wallpaper)
            }
        }

        print("Loaded \(wallpapers.count) wallpapers from library")
    }

    /// Imports a video file into the library
    func importVideo(from sourceURL: URL) async throws -> Wallpaper {
        let fileName = sourceURL.lastPathComponent
        let destURL = libraryURL.appendingPathComponent(fileName)

        // Check if file already exists
        if fileManager.fileExists(atPath: destURL.path) {
            // Generate unique name
            let uniqueName = UUID().uuidString + "_" + fileName
            let uniqueURL = libraryURL.appendingPathComponent(uniqueName)
            try fileManager.copyItem(at: sourceURL, to: uniqueURL)

            let wallpaper = Wallpaper(url: uniqueURL)
            await MainActor.run {
                wallpapers.append(wallpaper)
            }
            return wallpaper
        } else {
            try fileManager.copyItem(at: sourceURL, to: destURL)

            let wallpaper = Wallpaper(url: destURL)
            await MainActor.run {
                wallpapers.append(wallpaper)
            }
            return wallpaper
        }
    }

    /// Removes a wallpaper from the library
    func removeWallpaper(_ wallpaper: Wallpaper) {
        try? fileManager.removeItem(at: wallpaper.url)
        wallpapers.removeAll { $0.id == wallpaper.id }

        if currentWallpaper?.id == wallpaper.id {
            currentWallpaper = nil
        }
    }

    // MARK: - Playback

    /// Sets and plays a wallpaper
    func setWallpaper(_ wallpaper: Wallpaper) {
        currentWallpaper = wallpaper
        // Desktop window controller will be notified via observation
        NotificationCenter.default.post(
            name: .wallpaperDidChange,
            object: wallpaper
        )
    }

    func togglePlayback() {
        isPlaying.toggle()
        NotificationCenter.default.post(
            name: .playbackStateDidChange,
            object: isPlaying
        )
    }

    // MARK: - Helpers

    private func isVideoFile(_ url: URL) -> Bool {
        let videoExtensions = ["mp4", "mov", "m4v", "hevc"]
        return videoExtensions.contains(url.pathExtension.lowercased())
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let wallpaperDidChange = Notification.Name("wallpaperDidChange")
    static let playbackStateDidChange = Notification.Name("playbackStateDidChange")
}
