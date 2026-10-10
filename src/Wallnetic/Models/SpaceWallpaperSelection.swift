import Foundation

/// An app-owned recovery record. Its UUID identifies this selection, never a
/// macOS Space. No desktop index, display identity or window signature is saved.
struct SpaceWallpaperSelection: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var wallpaperPath: String
}

struct SpaceSelectionDocument: Codable {
    var version = 1
    var selections: [SpaceWallpaperSelection]

    static func validate(_ selections: [SpaceWallpaperSelection]) throws {
        guard selections.count <= 500,
              Set(selections.map(\.id)).count == selections.count,
              selections.allSatisfy({
                  !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  $0.name.count <= 80 && $0.wallpaperPath.utf8.count <= 8192
              }) else { throw SpaceSelectionError.invalidSelection }
    }
}

enum SpaceSelectionError: Error { case unreadable, invalidSelection }
