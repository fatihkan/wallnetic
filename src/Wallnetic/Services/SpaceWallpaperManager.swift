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
    // NOTE on identity: macOS does not expose a stable, App-Store-safe
    // Space identifier. Our signature is derived from Dock/Finder window
    // IDs (kernel-assigned, not portable across reboots), so assignments
    // keyed by signature do *not* survive a relaunch. We deliberately key
    // by signature anyway so a stale assignment cannot be applied to the
    // *wrong* Space — after a restart the user simply has to re-assign,
    // which is correct behavior in the face of unknown identity.
    @Published var spaceAssignments: [Int: String] = [:] // spaceID (signature) -> wallpaper URL path
    @Published var knownSpaceIDs: [Int] = [] // ordered list of discovered space IDs (current session)

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
        // spaceIndex is the position in knownSpaceIDs; resolve it to a
        // signature so the binding survives subsequent space discoveries
        // re-ordering the list.
        guard spaceIndex >= 0, spaceIndex < knownSpaceIDs.count else { return }
        let signature = knownSpaceIDs[spaceIndex]
        spaceAssignments[signature] = wallpaper.url.path
        saveAssignments()
        Log.space.info("Set wallpaper '\(wallpaper.name, privacy: .public)' for space signature \(signature)")

        if spaceIndex == currentSpaceIndex {
            WallpaperManager.shared.setWallpaper(wallpaper)
        }
    }

    func wallpaper(forSpace spaceIndex: Int) -> Wallpaper? {
        guard spaceIndex >= 0, spaceIndex < knownSpaceIDs.count else { return nil }
        let signature = knownSpaceIDs[spaceIndex]
        guard let path = spaceAssignments[signature] else { return nil }
        return WallpaperManager.shared.wallpapers.first { $0.url.path == path }
    }

    func clearAssignment(forSpace spaceIndex: Int) {
        guard spaceIndex >= 0, spaceIndex < knownSpaceIDs.count else { return }
        let signature = knownSpaceIDs[spaceIndex]
        spaceAssignments.removeValue(forKey: signature)
        saveAssignments()
    }

    /// Drops all per-Space assignments. UI surface should expose this so a
    /// user whose stored signatures no longer match (after restart) can
    /// reset state instead of seeing wallpapers go missing.
    func resetAllAssignments() {
        spaceAssignments.removeAll()
        saveAssignments()
        Log.space.info("Cleared all space assignments")
    }

    // MARK: - Space Detection

    private func onSpaceChanged() {
        let previousSpace = currentSpaceIndex
        detectCurrentSpace()

        guard currentSpaceIndex != previousSpace, isEnabled else { return }

        // Apply wallpaper for new space
        if let wallpaper = wallpaper(forSpace: currentSpaceIndex) {
            let idx = currentSpaceIndex
            Log.space.info("Space changed to \(idx), applying: \(wallpaper.name, privacy: .public)")
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
                Log.space.info("Space changed to index \(index)")
            }
        }
    }

    // MARK: - Persistence

    private func saveAssignments() {
        let stringKeyed = Dictionary(uniqueKeysWithValues: spaceAssignments.map { ("\($0.key)", $0.value) })
        do {
            let data = try JSONEncoder().encode(stringKeyed)
            if let json = String(data: data, encoding: .utf8) {
                assignmentsJSON = json
            }
        } catch {
            Log.space.error("Failed to persist space assignments: \(String(describing: error), privacy: .public)")
        }
    }

    private func loadAssignments() {
        guard let data = assignmentsJSON.data(using: .utf8) else { return }
        do {
            let decoded = try JSONDecoder().decode([String: String].self, from: data)
            // Stored keys are now space signatures, not indices. Pre-v1.3.1
            // saved data may still contain index keys (0,1,2…) — those
            // would never match a signature so they get harmlessly ignored,
            // which is the correct outcome (we don't know what space they
            // referred to).
            spaceAssignments = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
                guard let intKey = Int(key) else { return nil }
                return (intKey, value)
            })
        } catch {
            Log.space.error("Failed to decode space assignments; resetting. \(String(describing: error), privacy: .public)")
            assignmentsJSON = ""
        }
    }
}
