import Foundation
import AppKit

/// Handles `wallnetic://` URL scheme deep links.
///
/// Security model: deep links are reachable from any process or web page
/// that can spawn a `wallnetic://` URL — anyone the user clicks. State-
/// changing actions (especially `import` which downloads + imports a
/// remote file) require **explicit user confirmation** and limit the
/// allowed schemes to HTTPS to prevent `file://` exfiltration.
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

        // Log only host + path. Query string can contain tokens / credentials
        // from external referrers and should not be public-level diagnostic.
        let safe = "\(url.scheme ?? "")://\(url.host ?? "")\(url.path)"
        let queryLen = url.query?.count ?? 0
        Log.deepLink.info("\(safe, privacy: .public) [+\(queryLen) query chars]")

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
            handleImportAction(params: params)

        default:
            Log.deepLink.info("Unknown action: \(host, privacy: .public)")
        }
    }

    // MARK: - Import (sensitive — gated behind confirmation + HTTPS-only)

    private func handleImportAction(params: [String: String]) {
        guard let urlString = params["url"],
              let importURL = URL(string: urlString) else {
            Log.deepLink.error("import action with invalid URL")
            return
        }

        // Only allow HTTPS — `file://`, `ftp://`, custom schemes are denied
        // outright. URL scheme can be lower- or upper-case.
        guard importURL.scheme?.lowercased() == "https" else {
            Log.deepLink.error("import refused — non-HTTPS scheme: \(importURL.scheme ?? "nil", privacy: .public)")
            DispatchQueue.main.async {
                ErrorReporter.shared.report(
                    DeepLinkError.invalidScheme,
                    context: "Import refused: only HTTPS URLs are accepted from deep links."
                )
            }
            return
        }

        let host = importURL.host ?? "unknown source"

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Download wallpaper from \(host)?"
            alert.informativeText = "Wallnetic was asked to import a video from this URL:\n\n\(importURL.absoluteString)\n\nOnly proceed if you started this action."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Download & Import")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)

            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else {
                Log.deepLink.info("import cancelled by user")
                return
            }

            Task {
                do {
                    let downloaded = try await URLImporter.shared.downloadAndImport(from: urlString)
                    _ = try await WallpaperManager.shared.importVideo(from: downloaded)
                } catch {
                    await MainActor.run {
                        ErrorReporter.shared.report(error, context: "Import from deep link failed")
                    }
                }
            }
        }
    }
}

private enum DeepLinkError: LocalizedError {
    case invalidScheme

    var errorDescription: String? {
        switch self {
        case .invalidScheme: return "Only HTTPS URLs are accepted from deep links."
        }
    }
}
