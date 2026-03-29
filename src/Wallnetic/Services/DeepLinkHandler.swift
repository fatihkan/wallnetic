import Foundation

/// Handles wallnetic:// URL scheme deep links
class DeepLinkHandler {
    static let shared = DeepLinkHandler()

    private init() {}

    /// Process incoming URL
    func handle(_ url: URL) {
        guard url.scheme == "wallnetic" else { return }

        let host = url.host ?? ""
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let params = Dictionary(uniqueKeysWithValues:
            (components?.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            }
        )

        NSLog("[DeepLink] %@", url.absoluteString)

        switch host {
        case "playPause":
            WallpaperManager.shared.togglePlayback()

        case "nextWallpaper":
            WallpaperManager.shared.cycleToNextWallpaper()

        case "setWallpaper":
            if let idString = params["id"],
               let id = UUID(uuidString: idString),
               let wallpaper = WallpaperManager.shared.wallpapers.first(where: { $0.id == id }) {
                WallpaperManager.shared.setWallpaper(wallpaper)
            } else if let name = params["name"],
                      let wallpaper = WallpaperManager.shared.wallpapers.first(where: {
                          $0.name.localizedCaseInsensitiveContains(name)
                      }) {
                WallpaperManager.shared.setWallpaper(wallpaper)
            }

        case "random":
            let source = params["from"] ?? "all"
            let wallpapers = source == "favorites"
                ? WallpaperManager.shared.wallpapers.filter { $0.isFavorite }
                : WallpaperManager.shared.wallpapers
            if let random = wallpapers.randomElement() {
                WallpaperManager.shared.setWallpaper(random)
            }

        case "effects":
            if let preset = params["preset"],
               let found = WallpaperEffectsManager.presets.first(where: { $0.id == preset }) {
                WallpaperEffectsManager.shared.applyPreset(found)
            }

        case "import":
            if let urlString = params["url"] {
                Task {
                    let downloaded = try await URLImporter.shared.downloadAndImport(from: urlString)
                    _ = try await WallpaperManager.shared.importVideo(from: downloaded)
                }
            }

        default:
            NSLog("[DeepLink] Unknown action: %@", host)
        }
    }
}
