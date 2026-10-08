import AppKit

/// Paths survive library rescans, unlike the Wallpaper UUID recreated on load.
/// An empty path is an intentional empty display, not permission to inherit.
final class DisplayWallpaperAssignments {
    enum Selection: Equatable { case inherit, empty, file(URL) }
    private let defaults: UserDefaults
    private let key = "displayWallpaperPaths.v1"
    private var paths: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        paths = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    var hasAssignments: Bool { !paths.isEmpty }

    func selection(for display: String) -> Selection {
        guard let path = paths[display] else { return .inherit }
        return path.isEmpty ? .empty : .file(URL(fileURLWithPath: path))
    }

    func set(_ url: URL?, for display: String) {
        paths[display] = url?.standardizedFileURL.path ?? ""
        defaults.set(paths, forKey: key)
    }

    func remove(_ url: URL) {
        for display in paths.keys where paths[display] == url.standardizedFileURL.path {
            paths[display] = ""
        }
        defaults.set(paths, forKey: key)
    }
}

extension NSScreen {
    var wallpaperAssignmentKey: String {
        if let id = displayID, let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
           let value = CFUUIDCreateString(nil, uuid) {
            return value as String
        }
        return "name:\(localizedName)"
    }
}
