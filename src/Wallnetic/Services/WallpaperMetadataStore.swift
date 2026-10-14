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

    init(defaults: UserDefaults = .standard) {
        _favoriteWallpaperPaths = AppStorage(wrappedValue: "", "favoriteWallpaperPaths", store: defaults)
        _customWallpaperTitlesData = AppStorage(wrappedValue: "", "customWallpaperTitles", store: defaults)
        _wallpaperColorsData = AppStorage(wrappedValue: "", "wallpaperColors", store: defaults)
        _wallpaperTagsData = AppStorage(wrappedValue: "", "wallpaperTags", store: defaults)
    }

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

    /// Keep the full display title separate from the sanitized storage filename.
    /// Persist before publication so rescans/search use the same title.
    /// A previously saved user title always wins over a suggested download name.
    func applyImportedTitle(_ suggestedTitle: String?, to wallpaper: inout Wallpaper) {
        var titles = customTitles
        if let existing = titles[wallpaper.url.path] {
            wallpaper.customTitle = existing
            return
        }
        guard wallpaper.customTitle == nil,
              let title = Self.normalizedImportedTitle(suggestedTitle) else { return }
        wallpaper.customTitle = title
        titles[wallpaper.url.path] = title
        customTitles = titles
    }

    /// Also used before displaying untrusted page titles in download UI.
    static func normalizedImportedTitle(_ value: String?) -> String? {
        guard let value, value.utf8.count <= 4096 else { return nil }
        var scalars = String.UnicodeScalarView()
        for scalar in value.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                scalars.append(" ")
            } else if scalar.properties.generalCategory != .control,
                      scalar.value != 0x061C,
                      scalar.value != 0x200E, scalar.value != 0x200F,
                      !(0x202A...0x202E).contains(scalar.value),
                      !(0x2066...0x2069).contains(scalar.value) {
                scalars.append(scalar)
            }
        }
        let title = String(scalars).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return title.isEmpty ? nil : String(title.prefix(160))
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
