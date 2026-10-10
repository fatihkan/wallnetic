import XCTest
import AppKit
import Combine
@testable import Wallnetic

@MainActor
final class SpaceWallpaperRecoveryTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var library: [Wallpaper] = []
    private var applied: [String] = []
    private var missing = Set<String>()
    private var workspace = NotificationCenter()
    private var application = NotificationCenter()

    override func setUpWithError() throws {
        suite = "SpaceWallpaperRecoveryTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        library = ["first", "second"].map { Wallpaper(url: URL(fileURLWithPath: "/space-fixture/\($0).mp4")) }
        applied = []
        missing = []
        workspace = NotificationCenter()
        application = NotificationCenter()
    }

    override func tearDownWithError() throws { defaults.removePersistentDomain(forName: suite) }

    private func manager() -> SpaceWallpaperManager {
        SpaceWallpaperManager(defaults: defaults, library: { self.library },
            apply: { self.applied.append($0.url.path) }, fileExists: { !self.missing.contains($0.path) },
            workspaceCenter: workspace, applicationCenter: application)
    }

    private func choice(_ index: Int = 0) -> SpaceWallpaperSelection {
        SpaceWallpaperSelection(name: "Desk choice \(index)", wallpaperPath: library[index].url.path)
    }

    func testLegacyMigrationPreservesCollidingAndNonNumericKeysWithoutApplying() throws {
        let legacy = ["1": library[0].url.path, "01": library[1].url.path, "unknown": "/missing.mp4", "999": library[0].url.path]
        let json = String(data: try JSONEncoder().encode(legacy), encoding: .utf8)!
        defaults.set(json, forKey: SpaceWallpaperManager.legacyKey)
        defaults.set(true, forKey: "spaces.enabled")
        let recovered = manager()
        XCTAssertEqual(recovered.selections.count, 4)
        XCTAssertEqual(recovered.selections.map(\.wallpaperPath).sorted(), Array(legacy.values).sorted())
        XCTAssertEqual(Set(recovered.selections.map(\.id)).count, 4)
        XCTAssertEqual(recovered.recoveryReason, .legacyAssignments)
        XCTAssertNil(recovered.lastAppliedSelectionID)
        XCTAssertTrue(applied.isEmpty)
        XCTAssertEqual(defaults.string(forKey: SpaceWallpaperManager.legacyKey), json)
        XCTAssertEqual(manager().selections, recovered.selections, "Migrate once and keep app-owned selection IDs")
    }

    func testRelaunchKeepsIntentButNeverRestoresDesktopBinding() {
        let original = manager(), selection = choice()
        original.start()
        XCTAssertTrue(original.save(selection))
        XCTAssertTrue(original.applySelection(selection.id))
        let restored = manager()
        XCTAssertTrue(restored.isEnabled)
        XCTAssertEqual(restored.selections, [selection])
        XCTAssertNil(restored.lastAppliedSelectionID)
        XCTAssertEqual(restored.recoveryReason, .appOpened)
        XCTAssertEqual(applied.count, 1, "Relaunch does not apply a stale selection")
    }

    func testSpaceChangesNeverApplyEvenWhenDailyAndPlaylistAreOff() {
        let value = manager(), selection = choice()
        value.start()
        XCTAssertTrue(value.save(selection))
        XCTAssertTrue(value.applySelection(selection.id))
        let saved = defaults.data(forKey: SpaceWallpaperManager.documentKey)
        for _ in 0..<5 { workspace.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil) }
        XCTAssertEqual(applied.count, 1)
        XCTAssertNil(value.lastAppliedSelectionID)
        XCTAssertEqual(value.recoveryReason, .spaceChanged)
        XCTAssertEqual(value.selections, [selection])
        XCTAssertEqual(defaults.data(forKey: SpaceWallpaperManager.documentKey), saved)
    }

    func testDisplayChangeInvalidatesManualStatusAndAllowsExplicitRecovery() {
        let value = manager(), selection = choice()
        value.start()
        XCTAssertTrue(value.save(selection))
        XCTAssertTrue(value.applySelection(selection.id))
        application.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertNil(value.lastAppliedSelectionID)
        XCTAssertEqual(value.recoveryReason, .displaysChanged)
        XCTAssertEqual(applied.count, 1)
        XCTAssertTrue(value.applySelection(selection.id))
        XCTAssertEqual(applied, [selection.wallpaperPath, selection.wallpaperPath])
    }

    func testSleepWakeAndSessionChangesPreserveChoicesWithoutPlayback() {
        let value = manager(), selection = choice()
        value.start()
        XCTAssertTrue(value.save(selection))
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            XCTAssertTrue(value.applySelection(selection.id))
            let count = applied.count
            workspace.post(name: name, object: nil)
            XCTAssertNil(value.lastAppliedSelectionID)
            XCTAssertEqual(value.recoveryReason, .sessionChanged)
            XCTAssertEqual(value.selections, [selection])
            XCTAssertEqual(applied.count, count)
        }
    }

    func testRepeatedStartAndStopDoNotDuplicateOrRetainObservers() {
        let value = manager()
        value.start()
        value.start()
        var changes = 0
        let subscription = value.$recoveryReason.dropFirst().sink { _ in changes += 1 }
        workspace.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        XCTAssertEqual(changes, 1)
        value.stop()
        let stoppedCount = changes
        workspace.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        application.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertEqual(changes, stoppedCount)
        value.start()
        let restartedCount = changes
        workspace.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        XCTAssertEqual(changes, restartedCount + 1)
        withExtendedLifetime(subscription) {}
    }

    func testObserversDoNotKeepManagerAlive() {
        var value: SpaceWallpaperManager? = manager()
        value?.start()
        weak var weakValue = value
        value = nil
        XCTAssertNil(weakValue)
        workspace.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        XCTAssertTrue(applied.isEmpty)
    }

    func testSavingAndEditingNeverAppliesMedia() {
        let value = manager()
        value.start()
        XCTAssertTrue(value.saveForRecovery(library[0]))
        XCTAssertTrue(value.saveForRecovery(library[0]))
        XCTAssertEqual(value.selections.count, 1, "Repeated context-menu saves must not accumulate duplicates")
        var edited = value.selections[0]
        edited.name = "  Focus  "
        edited.wallpaperPath = library[1].url.path
        XCTAssertTrue(value.save(edited))
        XCTAssertEqual(value.selections[0].name, "Focus")
        XCTAssertEqual(value.selections[0].wallpaperPath, library[1].url.path)
        XCTAssertTrue(applied.isEmpty)
        XCTAssertNil(value.lastAppliedSelectionID)
    }

    func testMissingWallpaperRemainsVisibleAndCanBeReplacedFromLibrary() {
        let value = manager()
        var selection = SpaceWallpaperSelection(name: "Focus", wallpaperPath: "/unavailable/movie.mp4")
        value.start()
        XCTAssertTrue(value.save(selection))
        XCTAssertFalse(value.applySelection(selection.id))
        XCTAssertEqual(value.selections[0], selection)
        XCTAssertNotNil(value.error)
        selection.wallpaperPath = library[1].url.path
        XCTAssertTrue(value.save(selection))
        XCTAssertTrue(value.applySelection(selection.id))
        XCTAssertEqual(applied, [library[1].url.path])
        XCTAssertNil(value.error)
    }

    func testStaleLibraryEntryAndNetworkURLCannotBeApplied() {
        let value = manager(), selection = choice()
        value.start()
        XCTAssertTrue(value.save(selection))
        missing.insert(selection.wallpaperPath)
        XCTAssertNil(value.wallpaper(for: selection))
        XCTAssertFalse(value.applySelection(selection.id))
        let network = Wallpaper(url: URL(string: "https://example.invalid/remote.mp4")!)
        library.append(network)
        let remote = SpaceWallpaperSelection(name: "Remote", wallpaperPath: network.url.path)
        XCTAssertTrue(value.save(remote))
        XCTAssertFalse(value.applySelection(remote.id))
        XCTAssertTrue(applied.isEmpty)
    }

    func testExistingFileOutsideLibraryIsNeverResolvedBySavedPath() {
        let value = manager(), selection = choice()
        value.start()
        XCTAssertTrue(value.save(selection))
        library.removeAll() // fileExists still returns true.
        XCTAssertFalse(value.applySelection(selection.id))
        XCTAssertTrue(applied.isEmpty)
        XCTAssertEqual(value.selections, [selection])
    }

    func testLibraryRescanUsesPathInsteadOfTransientWallpaperUUID() {
        let value = manager(), selection = choice()
        value.start()
        XCTAssertTrue(value.save(selection))
        let oldID = library[0].id
        library[0] = Wallpaper(url: library[0].url)
        XCTAssertNotEqual(oldID, library[0].id)
        XCTAssertTrue(value.applySelection(selection.id))
        XCTAssertEqual(applied, [selection.wallpaperPath])
    }

    func testDisabledFeaturePreservesChoicesAndRefusesPlayback() {
        let value = manager(), selection = choice()
        XCTAssertTrue(value.save(selection))
        XCTAssertFalse(value.applySelection(selection.id))
        value.start()
        XCTAssertTrue(value.applySelection(selection.id))
        value.stop()
        XCTAssertFalse(value.applySelection(selection.id))
        XCTAssertFalse(value.saveForRecovery(library[1]))
        XCTAssertEqual(value.selections, [selection])
        XCTAssertNil(value.lastAppliedSelectionID)
        XCTAssertFalse(manager().isEnabled)
        XCTAssertEqual(applied.count, 1)
    }

    func testDeletingLibraryMediaClearsReferencesButKeepsNamedIntent() {
        let value = manager(), first = choice(), second = choice(1)
        value.start()
        XCTAssertTrue(value.save(first))
        XCTAssertTrue(value.save(second))
        XCTAssertTrue(value.applySelection(first.id))
        value.removeWallpaperPaths([first.wallpaperPath])
        XCTAssertEqual(value.selections.count, 2)
        XCTAssertEqual(value.selections[0].id, first.id)
        XCTAssertEqual(value.selections[0].name, first.name)
        XCTAssertEqual(value.selections[0].wallpaperPath, "")
        XCTAssertEqual(value.selections[1], second)
        XCTAssertNil(value.lastAppliedSelectionID)
        XCTAssertEqual(manager().selections, value.selections)
        XCTAssertEqual(applied.count, 1)
    }

    func testRemovedSelectionsDoNotResurrectFromLegacyData() throws {
        defaults.set("{\"123\":\"/old.mp4\"}", forKey: SpaceWallpaperManager.legacyKey)
        let value = manager()
        value.remove(try XCTUnwrap(value.selections.first?.id))
        XCTAssertTrue(manager().selections.isEmpty)
        XCTAssertNotNil(defaults.string(forKey: SpaceWallpaperManager.legacyKey))
    }

    func testMalformedLegacyDataIsPreservedUntilExplicitNewList() {
        let broken = "{\"old\": malformed"
        defaults.set(broken, forKey: SpaceWallpaperManager.legacyKey)
        let value = manager()
        XCTAssertTrue(value.hasUnreadableData)
        XCTAssertFalse(value.save(choice()))
        XCTAssertEqual(defaults.string(forKey: SpaceWallpaperManager.legacyKey), broken)
        XCTAssertNil(defaults.object(forKey: SpaceWallpaperManager.documentKey))
        XCTAssertTrue(value.startNewList())
        XCTAssertFalse(value.hasUnreadableData)
        XCTAssertTrue(value.save(choice()))
        XCTAssertEqual(defaults.string(forKey: SpaceWallpaperManager.legacyKey), broken)
    }

    func testFutureVersionIsNotSilentlyDowngradedOrReplacedByLegacy() throws {
        let data = try JSONEncoder().encode(SpaceSelectionDocument(version: 42, selections: [choice()]))
        defaults.set(data, forKey: SpaceWallpaperManager.documentKey)
        defaults.set("{\"123\":\"/old.mp4\"}", forKey: SpaceWallpaperManager.legacyKey)
        let value = manager()
        XCTAssertTrue(value.hasUnreadableData)
        XCTAssertTrue(value.selections.isEmpty)
        XCTAssertFalse(value.save(choice(1)))
        value.remove(UUID())
        XCTAssertEqual(defaults.data(forKey: SpaceWallpaperManager.documentKey), data)
        XCTAssertTrue(value.startNewList())
        let backups = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix(SpaceWallpaperManager.documentKey + ".backup.") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(backups.values.first as? Data, data)
        XCTAssertFalse(manager().hasUnreadableData)
        XCTAssertTrue(manager().selections.isEmpty)
    }

    func testInvalidStoredTypeAndDuplicateRecordIDsAreRejectedWithoutMutation() throws {
        let selection = choice()
        let duplicates = try JSONEncoder().encode(SpaceSelectionDocument(selections: [selection, selection]))
        for original: Any in ["wrong storage type", Data("broken".utf8), duplicates] {
            defaults.set(original, forKey: SpaceWallpaperManager.documentKey)
            let value = manager()
            XCTAssertTrue(value.hasUnreadableData)
            XCTAssertFalse(value.save(selection))
            if let data = original as? Data { XCTAssertEqual(defaults.data(forKey: SpaceWallpaperManager.documentKey), data) }
            else { XCTAssertEqual(defaults.string(forKey: SpaceWallpaperManager.documentKey), original as? String) }
        }
    }

    func testInvalidEditsLeaveLastValidDocumentIntact() {
        let value = manager(), valid = choice()
        XCTAssertTrue(value.save(valid))
        let saved = defaults.data(forKey: SpaceWallpaperManager.documentKey)
        for name in ["  \n  ", String(repeating: "x", count: 81)] {
            var invalid = valid
            invalid.name = name
            XCTAssertFalse(value.save(invalid))
            XCTAssertEqual(value.selections, [valid])
            XCTAssertEqual(defaults.data(forKey: SpaceWallpaperManager.documentKey), saved)
        }
    }
}
