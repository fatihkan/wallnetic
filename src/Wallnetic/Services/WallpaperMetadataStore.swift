import Foundation
import SwiftUI

/// Persists wallpaper metadata (custom titles, colors, tags, favorites)
/// via AppStorage-backed JSON strings with in-memory caching.
final class WallpaperMetadataStore {
    static let shared = WallpaperMetadataStore()

    // MARK: - AppStorage backing (via UserDefaults)

    @AppStorage("favoriteWallpaperPaths") private var favoriteWallpaperPaths: String = ""
    @AppStorage("customWallpaperTitles") private var customWallpaperTitlesData: String = ""
    @AppStorage("wallpaperColors") private var wallpaperColorsData: String = ""
    @AppStorage("wallpaperTags") private var wallpaperTagsData: String = ""

    // MARK: - In-memory caches (avoid repeated JSON decode)

    private var _customTitles: [String: String]?
    private var _savedColors: [String: String]?
    private var _savedTags: [String: [String]]?

    private init() {}

    // MARK: - Favorites

    var favoritePaths: Set<String> {
        get { Set(favoriteWallpaperPaths.split(separator: "\n").map(String.init)) }
        set { favoriteWallpaperPaths = newValue.joined(separator: "\n") }
    }

    func saveFavorites(from wallpapers: [Wallpaper]) {
        let paths = wallpapers.filter { $0.isFavorite }.map { $0.url.path }
        favoritePaths = Set(paths)
    }

    // MARK: - Custom Titles

    var customTitles: [String: String] {
        get {
            if let cached = _customTitles { return cached }
            let decoded = decodeJSON(customWallpaperTitlesData, as: [String: String].self)
            _customTitles = decoded
            return decoded
        }
        set {
            _customTitles = newValue
            customWallpaperTitlesData = encodeJSON(newValue)
        }
    }

    func applyCustomTitles(to wallpapers: inout [Wallpaper]) {
        let titles = customTitles
        guard !titles.isEmpty else { return }
        for i in wallpapers.indices {
            if let title = titles[wallpapers[i].url.path] {
                wallpapers[i].customTitle = title
            }
        }
    }

    func saveCustomTitles(from wallpapers: [Wallpaper]) {
        var titles: [String: String] = [:]
        for wp in wallpapers where wp.customTitle != nil {
            titles[wp.url.path] = wp.customTitle
        }
        customTitles = titles
    }

    // MARK: - Dominant Colors

    var savedColors: [String: String] {
        get {
            if let cached = _savedColors { return cached }
            let decoded = decodeJSON(wallpaperColorsData, as: [String: String].self)
            _savedColors = decoded
            return decoded
        }
        set {
            _savedColors = newValue
            wallpaperColorsData = encodeJSON(newValue)
        }
    }

    func applySavedColors(to wallpapers: inout [Wallpaper]) {
        let colors = savedColors
        guard !colors.isEmpty else { return }
        for i in wallpapers.indices {
            if let hex = colors[wallpapers[i].url.path] {
                wallpapers[i].dominantColorHex = hex
            }
        }
    }

    // MARK: - Tags

    var savedTags: [String: [String]] {
        get {
            if let cached = _savedTags { return cached }
            let decoded = decodeJSON(wallpaperTagsData, as: [String: [String]].self)
            _savedTags = decoded
            return decoded
        }
        set {
            _savedTags = newValue
            wallpaperTagsData = encodeJSON(newValue)
        }
    }

    func applySavedTags(to wallpapers: inout [Wallpaper]) {
        let tags = savedTags
        guard !tags.isEmpty else { return }
        for i in wallpapers.indices {
            if let t = tags[wallpapers[i].url.path] {
                wallpapers[i].tags = t
            }
        }
    }

    // MARK: - Generic JSON helpers

    private func decodeJSON<T: Decodable>(_ string: String, as type: T.Type) -> T where T: ExpressibleByDictionaryLiteral {
        let empty: T = [:]
        guard !string.isEmpty, let data = string.data(using: .utf8) else { return empty }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            Log.app.error("WallpaperMetadataStore decode failed for \(String(describing: T.self), privacy: .public); resetting cache. Error: \(String(describing: error), privacy: .public)")
            return empty
        }
    }

    private func encodeJSON<T: Encodable>(_ value: T) -> String {
        do {
            let data = try JSONEncoder().encode(value)
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            Log.app.error("WallpaperMetadataStore encode failed for \(String(describing: T.self), privacy: .public): \(String(describing: error), privacy: .public)")
            return ""
        }
    }
}
