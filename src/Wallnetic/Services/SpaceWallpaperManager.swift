import Foundation
import SwiftUI
import Cocoa

/// Manages different wallpapers per macOS Space (virtual desktop)
class SpaceWallpaperManager: ObservableObject {
    static let shared = SpaceWallpaperManager()

    @AppStorage("spaces.enabled") var isEnabled: Bool = false
    @AppStorage("spaces.assignmentsJSON") private var assignmentsJSON: String = "{}"

    @Published var currentSpaceIndex: Int = 0
    @Published var currentSpaceID: Int = 0
    @Published var spaceAssignments: [Int: String] = [:] // spaceIndex -> wallpaper URL path
    @Published var knownSpaceIDs: [Int] = [] // ordered list of discovered space IDs

    private var spaceObserver: Any?

    private init() {
        loadAssignments()
        detectCurrentSpace()
        if isEnabled { start() }
    }

    // MARK: - Control

    func start() {
        isEnabled = true
        detectCurrentSpace()

        // Remove existing observer if any (prevent double registration)
        if let existing = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(existing)
        }

        // Observe space changes
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onSpaceChanged()
        }
    }

    func stop() {
        isEnabled = false
        if let observer = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceObserver = nil
        }
    }

    // MARK: - Assignment

    func setWallpaper(_ wallpaper: Wallpaper, forSpace spaceIndex: Int) {
        spaceAssignments[spaceIndex] = wallpaper.url.path
        saveAssignments()
        NSLog("[Spaces] Set wallpaper '%@' for space %d", wallpaper.name, spaceIndex)

        // Apply immediately if this is the current space
        if spaceIndex == currentSpaceIndex {
            WallpaperManager.shared.setWallpaper(wallpaper)
        }
    }

    func wallpaper(forSpace spaceIndex: Int) -> Wallpaper? {
        guard let path = spaceAssignments[spaceIndex] else { return nil }
        return WallpaperManager.shared.wallpapers.first { $0.url.path == path }
    }

    func clearAssignment(forSpace spaceIndex: Int) {
        spaceAssignments.removeValue(forKey: spaceIndex)
        saveAssignments()
    }

    // MARK: - Space Detection

    private func onSpaceChanged() {
        let previousSpace = currentSpaceIndex
        detectCurrentSpace()

        guard currentSpaceIndex != previousSpace, isEnabled else { return }

        // Apply wallpaper for new space
        if let wallpaper = wallpaper(forSpace: currentSpaceIndex) {
            NSLog("[Spaces] Space changed to %d, applying: %@", currentSpaceIndex, wallpaper.name)
            WallpaperManager.shared.setWallpaper(wallpaper)
        }
    }

    private func detectCurrentSpace() {
        // Use window list to detect space changes (App Store safe)
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return
        }

        // Count visible Dock windows as a proxy for space identification
        var spaceSignature = 0
        for info in windowList {
            if let owner = info[kCGWindowOwnerName as String] as? String,
               owner == "Dock" || owner == "Finder",
               let wid = info[kCGWindowNumber as String] as? Int {
                spaceSignature = spaceSignature &+ wid
            }
        }

        guard spaceSignature != 0 else { return }

        currentSpaceID = spaceSignature

        if !knownSpaceIDs.contains(spaceSignature) {
            knownSpaceIDs.append(spaceSignature)
        }

        if let index = knownSpaceIDs.firstIndex(of: spaceSignature) {
            if index != currentSpaceIndex {
                currentSpaceIndex = index
                NSLog("[Spaces] Space changed to index %d", index)
            }
        }
    }

    // MARK: - Persistence

    private func saveAssignments() {
        let stringKeyed = Dictionary(uniqueKeysWithValues: spaceAssignments.map { ("\($0.key)", $0.value) })
        if let data = try? JSONEncoder().encode(stringKeyed),
           let json = String(data: data, encoding: .utf8) {
            assignmentsJSON = json
        }
    }

    private func loadAssignments() {
        guard let data = assignmentsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        spaceAssignments = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
            guard let intKey = Int(key) else { return nil }
            return (intKey, value)
        })
    }
}
