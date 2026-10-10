import AppKit
import Combine

/// Saves user intent, never Space identity. Public workspace notifications have
/// no desktop identifier; window-number sums cannot safely restore an assignment.
/// Mutations and notification delivery run on the main thread, like the other
/// wallpaper managers. Only an explicit apply can start playback.
final class SpaceWallpaperManager: ObservableObject {
    static let shared = SpaceWallpaperManager(
        library: { WallpaperManager.shared.wallpapers },
        apply: { WallpaperManager.shared.setWallpaper($0, userInitiated: true) })
    static let documentKey = "spaces.selections.v1"
    static let legacyKey = "spaces.assignmentsJSON"

    enum RecoveryReason: String {
        case appOpened = "Saved choices need reassignment after opening the app."
        case legacyAssignments = "Previous Space assignments were kept as saved choices. Choose one to apply manually."
        case spaceChanged = "The active desktop changed. Saved choices need reassignment."
        case displaysChanged = "The display setup changed. Saved choices need reassignment."
        case sessionChanged = "The Mac slept or the login session changed. Saved choices need reassignment."
        case disabled = "Saved choices are kept while Space recovery is off."
        case enabled = "Choose a saved wallpaper to apply manually."
    }

    @Published private(set) var isEnabled: Bool
    @Published private(set) var selections: [SpaceWallpaperSelection] = []
    @Published private(set) var lastAppliedSelectionID: UUID?
    @Published private(set) var recoveryReason: RecoveryReason = .appOpened
    @Published private(set) var hasUnreadableData = false
    @Published private(set) var error: String?

    private let defaults: UserDefaults
    private let library: () -> [Wallpaper]
    private let apply: (Wallpaper) -> Void
    private let fileExists: (URL) -> Bool
    private let workspaceCenter: NotificationCenter
    private let applicationCenter: NotificationCenter
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(defaults: UserDefaults = .standard,
         library: @escaping () -> [Wallpaper], apply: @escaping (Wallpaper) -> Void,
         fileExists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
         workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
         applicationCenter: NotificationCenter = .default) {
        self.defaults = defaults
        self.library = library
        self.apply = apply
        self.fileExists = fileExists
        self.workspaceCenter = workspaceCenter
        self.applicationCenter = applicationCenter
        isEnabled = defaults.bool(forKey: "spaces.enabled")
        loadSelections()
        if isEnabled { observeChanges() }
        else { recoveryReason = .disabled }
    }

    deinit {
        for (center, observer) in observers { center.removeObserver(observer) }
    }

    func start() {
        if !isEnabled { invalidate(.enabled) }
        isEnabled = true
        defaults.set(true, forKey: "spaces.enabled")
        observeChanges()
    }

    func stop() {
        isEnabled = false
        defaults.set(false, forKey: "spaces.enabled")
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        invalidate(.disabled)
    }

    /// A saved path is never permission to import arbitrary media or make a
    /// network request. It must still resolve to an available library item.
    func wallpaper(for selection: SpaceWallpaperSelection) -> Wallpaper? {
        guard !selection.wallpaperPath.isEmpty else { return nil }
        return library().first {
            $0.url.isFileURL && $0.url.path == selection.wallpaperPath && fileExists($0.url)
        }
    }

    @discardableResult
    func save(_ selection: SpaceWallpaperSelection) -> Bool {
        var candidate = selections
        var selection = selection
        selection.name = selection.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = candidate.firstIndex(where: { $0.id == selection.id }) { candidate[index] = selection }
        else { candidate.append(selection) }
        guard persist(candidate) else { return false }
        if lastAppliedSelectionID == selection.id { lastAppliedSelectionID = nil }
        return true
    }

    /// Saving never claims to bind the wallpaper to the current desktop.
    @discardableResult
    func saveForRecovery(_ wallpaper: Wallpaper) -> Bool {
        guard isEnabled, !hasUnreadableData else { return false }
        if selections.contains(where: { $0.wallpaperPath == wallpaper.url.path }) { return true }
        let name = wallpaper.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return save(SpaceWallpaperSelection(name: name.isEmpty ? "Wallpaper" : String(name.prefix(80)),
                                            wallpaperPath: wallpaper.url.path))
    }

    @discardableResult
    func applySelection(_ id: UUID) -> Bool {
        guard isEnabled, !hasUnreadableData else { return false }
        guard let selection = selections.first(where: { $0.id == id }),
              let wallpaper = wallpaper(for: selection) else {
            error = "This wallpaper is unavailable. Edit the saved choice to select a wallpaper from Library."
            return false
        }
        apply(wallpaper)
        lastAppliedSelectionID = id
        error = nil
        return true
    }

    func remove(_ id: UUID) {
        if persist(selections.filter { $0.id != id }), lastAppliedSelectionID == id {
            lastAppliedSelectionID = nil
        }
    }

    func removeWallpaperPaths(_ paths: Set<String>) {
        guard selections.contains(where: { paths.contains($0.wallpaperPath) }) else { return }
        let affectedIDs = Set(selections.filter { paths.contains($0.wallpaperPath) }.map(\.id))
        let candidate = selections.map { selection -> SpaceWallpaperSelection in
            var selection = selection
            if affectedIDs.contains(selection.id) { selection.wallpaperPath = "" }
            return selection
        }
        if persist(candidate), let id = lastAppliedSelectionID, affectedIDs.contains(id) {
            lastAppliedSelectionID = nil
        }
    }

    /// UI confirms this explicit recovery action. Retain unreadable/future data.
    @discardableResult
    func startNewList() -> Bool {
        guard hasUnreadableData else { return false }
        if let original = defaults.object(forKey: Self.documentKey) {
            defaults.set(original, forKey: Self.documentKey + ".backup." + UUID().uuidString)
        }
        // The legacy key is always left intact, including invalid JSON.
        guard write([]) else { return false }
        hasUnreadableData = false
        selections = []
        lastAppliedSelectionID = nil
        recoveryReason = isEnabled ? .enabled : .disabled
        error = nil
        return true
    }

    func dismissError() { if !hasUnreadableData { error = nil } }

    private func invalidate(_ reason: RecoveryReason) {
        lastAppliedSelectionID = nil
        recoveryReason = reason
        // No wallpaper lookup or playback, even with other automation disabled:
        // an unknown desktop must never match a saved selection automatically.
    }

    private func observeChanges() {
        guard observers.isEmpty else { return }
        observe(NSWorkspace.activeSpaceDidChangeNotification, on: workspaceCenter, reason: .spaceChanged)
        observe(NSApplication.didChangeScreenParametersNotification, on: applicationCenter, reason: .displaysChanged)
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observe(name, on: workspaceCenter, reason: .sessionChanged)
        }
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter, reason: RecoveryReason) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            self?.invalidate(reason)
        }
        observers.append((center, observer))
    }

    private func loadSelections() {
        do {
            if let original = defaults.object(forKey: Self.documentKey) {
                guard let data = original as? Data, data.count <= 2_000_000 else {
                    throw SpaceSelectionError.unreadable
                }
                let document = try JSONDecoder().decode(SpaceSelectionDocument.self, from: data)
                guard document.version == 1 else { throw SpaceSelectionError.unreadable }
                try SpaceSelectionDocument.validate(document.selections)
                selections = document.selections
            } else if let original = defaults.object(forKey: Self.legacyKey) {
                guard let json = original as? String, let data = json.data(using: .utf8),
                      data.count <= 2_000_000 else { throw SpaceSelectionError.unreadable }
                let legacy = try JSONDecoder().decode([String: String].self, from: data)
                // Preserve every value: keys such as "1" and "01" must not
                // collide (the former Int-key conversion could crash here).
                let recovered = legacy.sorted { $0.key < $1.key }.enumerated().map { index, entry in
                    SpaceWallpaperSelection(name: "Saved choice \(index + 1)", wallpaperPath: entry.value)
                }
                try SpaceSelectionDocument.validate(recovered)
                guard write(recovered) else { throw SpaceSelectionError.unreadable }
                selections = recovered
                if !recovered.isEmpty { recoveryReason = .legacyAssignments }
            }
        } catch {
            hasUnreadableData = true
            self.error = "Saved Space choices could not be read. The original data has been kept."
        }
    }

    private func persist(_ candidate: [SpaceWallpaperSelection]) -> Bool {
        guard !hasUnreadableData, write(candidate) else { return false }
        selections = candidate
        error = nil
        return true
    }

    private func write(_ candidate: [SpaceWallpaperSelection]) -> Bool {
        do {
            try SpaceSelectionDocument.validate(candidate)
            let data = try JSONEncoder().encode(SpaceSelectionDocument(selections: candidate))
            guard data.count <= 2_000_000 else { throw SpaceSelectionError.invalidSelection }
            defaults.set(data, forKey: Self.documentKey)
            return true
        } catch {
            self.error = "Use a name of 1–80 characters and keep up to 500 saved choices."
            return false
        }
    }
}
