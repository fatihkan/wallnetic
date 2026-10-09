import XCTest
import Darwin
@testable import Wallnetic

final class LibraryStorageTests: XCTestCase {
    private var root: URL!
    private var service: LibraryStorage!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(UUID().uuidString)
        service = LibraryStorage(libraryURL: root.appendingPathComponent("Library"),
                                 framesURL: root.appendingPathComponent("Frames"),
                                 thumbnailsURL: root.appendingPathComponent("Thumbnails"),
                                 metadataURL: root.appendingPathComponent("metadata.sqlite"))
        try FileManager.default.createDirectory(at: service.libraryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root, FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    @discardableResult
    private func file(_ url: URL, bytes: Int) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
        return url
    }

    func testBreakdownCountsOnlyOwnedContentAndProtectsRequiredCaches() throws {
        try file(service.libraryURL.appendingPathComponent("video.mp4"), bytes: 100)
        try file(service.framesURL.appendingPathComponent("frame-0123456789abcdef.jpg"), bytes: 20)
        let protected = UUID().uuidString + ".jpg"
        try file(service.thumbnailsURL!.appendingPathComponent(protected), bytes: 30)
        try file(service.thumbnailsURL!.appendingPathComponent(UUID().uuidString + ".jpg"), bytes: 40)
        try file(service.metadataURL, bytes: 50)
        try file(root.appendingPathComponent("original.mp4"), bytes: 900)
        try file(service.libraryURL.appendingPathComponent("notes.txt"), bytes: 900)
        let scan = try service.scan(protectedThumbnailNames: [protected])
        XCTAssertEqual(scan.totalBytes, 240)
        XCTAssertEqual(scan.bytes(in: .videos), 100)
        XCTAssertEqual(scan.bytes(in: .generated), 20)
        XCTAssertEqual(scan.bytes(in: .caches), 120)
        XCTAssertEqual(scan.items.filter(\.canRemove).count, 2)
        XCTAssertTrue(scan.failures.isEmpty, scan.failures.joined(separator: "; "))
    }

    func testBulkRemovalPreservesOriginalsAndOnlyRemovesSelectedCopiesOnce() throws {
        let original = try file(root.appendingPathComponent("original.mp4"), bytes: 40)
        let copy = service.libraryURL.appendingPathComponent("copy.mp4")
        try FileManager.default.copyItem(at: original, to: copy)
        let kept = try file(service.libraryURL.appendingPathComponent("keep.mov"), bytes: 30)
        let item = try XCTUnwrap(service.scan().items.first { $0.url == copy })
        let result = service.remove([item, item])
        XCTAssertEqual(result.removed.count, 1)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(try Data(contentsOf: original).count, 40)
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
    }

    func testSymlinksAndDirectoriesAreReportedAndNeverFollowed() throws {
        let original = try file(root.appendingPathComponent("original.mp4"), bytes: 50)
        try FileManager.default.createSymbolicLink(at: service.libraryURL.appendingPathComponent("link.mp4"), withDestinationURL: original)
        let nested = service.libraryURL.appendingPathComponent("folder.mp4")
        try file(nested.appendingPathComponent("private.mp4"), bytes: 60)
        let scan = try service.scan()
        XCTAssertTrue(scan.items.isEmpty)
        XCTAssertEqual(scan.failures.count, 2)
        XCTAssertEqual(try Data(contentsOf: original).count, 50)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.appendingPathComponent("private.mp4").path))
    }

    func testChangedAndMissingFilesFailIndividuallyWithoutDeletingOtherData() throws {
        let changed = try file(service.libraryURL.appendingPathComponent("changed.mp4"), bytes: 10)
        let missing = try file(service.libraryURL.appendingPathComponent("missing.mp4"), bytes: 20)
        try file(service.libraryURL.appendingPathComponent("remove.mp4"), bytes: 30)
        let scan = try service.scan()
        try Data(repeating: 9, count: 50).write(to: changed)
        try FileManager.default.removeItem(at: missing)
        let result = service.remove(scan.items)
        XCTAssertEqual(result.removed.count, 1)
        XCTAssertEqual(result.failures.count, 2)
        XCTAssertEqual(try Data(contentsOf: changed).count, 50)
    }

    func testSameSizeReplacementAndSymlinkSwapAfterConfirmationAreRejected() throws {
        let target = try file(service.libraryURL.appendingPathComponent("copy.mp4"), bytes: 12)
        let original = try file(root.appendingPathComponent("original.mp4"), bytes: 12)
        let item = try XCTUnwrap(service.scan().items.first)
        // Keep the old inode alive so replacement cannot reuse it.
        try FileManager.default.moveItem(at: target, to: root.appendingPathComponent("old.mp4"))
        try FileManager.default.copyItem(at: original, to: target)
        XCTAssertEqual(service.remove([item]).failures.count, 1)
        try FileManager.default.removeItem(at: target)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: original)
        XCTAssertEqual(service.remove([item]).failures.count, 1)
        XCTAssertEqual(try Data(contentsOf: original).count, 12)
    }

    func testReplacedOwnedDirectoryCannotRedirectDeletion() throws {
        try file(service.libraryURL.appendingPathComponent("copy.mp4"), bytes: 12)
        let item = try XCTUnwrap(service.scan().items.first)
        let old = root.appendingPathComponent("OldLibrary")
        try FileManager.default.moveItem(at: service.libraryURL, to: old)
        try FileManager.default.createSymbolicLink(at: service.libraryURL, withDestinationURL: old)
        XCTAssertEqual(service.remove([item]).failures.count, 1)
        XCTAssertTrue(try service.scan().items.isEmpty)
        try FileManager.default.removeItem(at: service.libraryURL)
        try file(service.libraryURL.appendingPathComponent("copy.mp4"), bytes: 12)
        XCTAssertEqual(service.remove([item]).failures.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.appendingPathComponent("copy.mp4").path))
    }

    func testForeignSnapshotCannotDeleteOutsideThisLibrary() throws {
        let other = LibraryStorage(libraryURL: root.appendingPathComponent("Other"), framesURL: service.framesURL,
                                   thumbnailsURL: nil, metadataURL: service.metadataURL)
        let original = try file(other.libraryURL.appendingPathComponent("original.mp4"), bytes: 70)
        let item = try XCTUnwrap(other.scan().items.first { $0.category == .videos })
        XCTAssertEqual(service.remove([item]).failures.count, 1)
        XCTAssertEqual(try Data(contentsOf: original).count, 70)
    }

    func testContainerParentAliasKeepsAssignmentPathsAndRejectsRetargeting() throws {
        let physical = root.appendingPathComponent("Physical")
        let copy = try file(physical.appendingPathComponent("Library/copy.mp4"), bytes: 15)
        let alias = root.appendingPathComponent("ContainerAlias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: physical)
        let logicalLibrary = alias.appendingPathComponent("Library")
        let storage = LibraryStorage(libraryURL: logicalLibrary, framesURL: service.framesURL,
                                     thumbnailsURL: nil, metadataURL: service.metadataURL)
        let wallpaper = Wallpaper(url: logicalLibrary.appendingPathComponent("copy.mp4"))
        let item = try XCTUnwrap(storage.scan().items.first { $0.category == .videos })
        XCTAssertEqual(item.url, wallpaper.url)
        try FileManager.default.removeItem(at: alias)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        XCTAssertEqual(storage.remove([item]).failures.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
        try FileManager.default.removeItem(at: alias)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: physical)
        let result = storage.remove([item])
        XCTAssertEqual(result.removed.count, 1)
        let update = LibraryRemovalState(result: result, wallpapers: [wallpaper], current: wallpaper, screenAssignments: [:])
        XCTAssertNil(update.current)
        XCTAssertTrue(update.wallpapers.isEmpty)
    }

    func testCacheCleanupRechecksNewlyProtectedThumbnailsAndKeepsVideosAndStills() throws {
        let name = UUID().uuidString + ".jpg"
        try file(service.thumbnailsURL!.appendingPathComponent(name), bytes: 10)
        try file(service.thumbnailsURL!.appendingPathComponent(UUID().uuidString + ".jpg"), bytes: 20)
        let video = try file(service.libraryURL.appendingPathComponent("video.mp4"), bytes: 30)
        let still = try file(service.framesURL.appendingPathComponent("frame-0123456789abcdef.jpg"), bytes: 40)
        let scan = try service.scan()
        let result = service.remove(scan.items.filter { $0.category != .videos }, protectedThumbnailNames: [name])
        XCTAssertEqual(result.removed.count, 1)
        XCTAssertEqual(result.failures.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: video.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: still.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: service.thumbnailsURL!.appendingPathComponent(name).path))
    }

    func testCancelledScanStopsBeforeEnumerating() async throws {
        let storage = try XCTUnwrap(service)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try storage.scan()
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
    }

    func testWidgetReferencesRejectLinksPipesAndOversizedRecordsWithoutReadingTargets() throws {
        let target = try file(root.appendingPathComponent("target.json"), bytes: 10)
        let link = root.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try SharedDataManager.readStorageReferences(at: link))
        let pipe = root.appendingPathComponent("pipe.json")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        XCTAssertThrowsError(try SharedDataManager.readStorageReferences(at: pipe))
        let large = try file(root.appendingPathComponent("large.json"), bytes: 1_048_577)
        XCTAssertThrowsError(try SharedDataManager.readStorageReferences(at: large))
        XCTAssertEqual(try Data(contentsOf: target).count, 10)
    }

    func testWidgetReferencesDistinguishMissingFromCorruptRecords() throws {
        let url = root.appendingPathComponent("widget.json")
        XCTAssertNil(try SharedDataManager.readStorageReferences(at: url).currentThumbnailPath)
        var shared = SharedWidgetData()
        shared.currentThumbnailPath = UUID().uuidString + ".jpg"
        try JSONEncoder().encode(shared).write(to: url)
        XCTAssertEqual(try SharedDataManager.readStorageReferences(at: url).currentThumbnailPath, shared.currentThumbnailPath)
        try Data("broken JSON".utf8).write(to: url)
        XCTAssertThrowsError(try SharedDataManager.readStorageReferences(at: url))
    }

    func testLibraryRescanKeepsIDsForCollectionAndDisplayReferences() throws {
        try file(service.libraryURL.appendingPathComponent("keep.mp4"), bytes: 10)
        let library = WallpaperLibrary(directory: service.libraryURL)
        let first = library.loadAll(favoritePaths: [])
        try file(service.libraryURL.appendingPathComponent("new.mp4"), bytes: 20)
        let rescanned = library.loadAll(favoritePaths: [], existingIDs: Dictionary(uniqueKeysWithValues: first.map { ($0.url.path, $0.id) }))
        XCTAssertEqual(rescanned.first { $0.url == first[0].url }?.id, first[0].id)
        XCTAssertEqual(Set(rescanned.map(\.id)).count, 2)
    }

    func testOnlySuccessfulRemovalClearsActiveAndDisplayReferencesDespiteOldIDs() throws {
        let deletedURL = try file(service.libraryURL.appendingPathComponent("delete.mp4"), bytes: 10)
        let keptURL = try file(service.libraryURL.appendingPathComponent("keep.mp4"), bytes: 20)
        let current = Wallpaper(url: deletedURL)
        let reloaded = Wallpaper(url: deletedURL)
        let kept = Wallpaper(url: keptURL)
        let wallpapers = [reloaded, kept]
        let displays = ["old-current": current.id, "reloaded": reloaded.id, "keep": kept.id]
        let before = LibraryRemovalState(result: StorageRemovalResult(failures: ["Permission denied"]),
                                         wallpapers: wallpapers, current: current, screenAssignments: displays)
        XCTAssertEqual(before.current?.id, current.id)
        XCTAssertEqual(before.screenAssignments, displays)
        XCTAssertEqual(before.wallpapers.count, 2)
        let item = try XCTUnwrap(service.scan().items.first { $0.url == deletedURL })
        let after = LibraryRemovalState(result: service.remove([item]), wallpapers: wallpapers,
                                        current: current, screenAssignments: displays)
        XCTAssertNil(after.current)
        XCTAssertEqual(after.wallpapers.map(\.id), [kept.id])
        XCTAssertEqual(after.screenAssignments, ["keep": kept.id])
        XCTAssertEqual(after.ids, [current.id, reloaded.id])
    }

    @MainActor
    func testLateWidgetSyncCannotRestoreDeletedCurrentWallpaperOrFavorites() async throws {
        let removed = Wallpaper(url: service.libraryURL.appendingPathComponent("deleted.mp4"), isFavorite: true)
        let sink = StorageWidgetSink()
        var continuation: CheckedContinuation<NSImage?, Never>?
        let sync = WidgetSyncService(writer: { sink }, thumbnail: { _, _ in
            await withCheckedContinuation { continuation = $0 }
        })
        let old = sync.syncAll(current: removed, isPlaying: true, wallpapers: [removed])
        while continuation == nil { await Task.yield() }
        await sync.syncAll(current: nil, isPlaying: false, wallpapers: []).value
        continuation?.resume(returning: nil)
        await old.value
        XCTAssertNil(sink.currentID)
        XCTAssertTrue(sink.favorites.isEmpty)
        XCTAssertFalse(sink.isPlaying)
        XCTAssertEqual(sink.currentWrites, 1, "A stale thumbnail task must not republish a deleted wallpaper")
    }

    @MainActor
    func testLateFavoriteThumbnailCannotRestoreRemovedFavorites() async {
        let removed = Wallpaper(url: service.libraryURL.appendingPathComponent("deleted.mp4"), isFavorite: true)
        let sink = StorageWidgetSink()
        var continuation: CheckedContinuation<NSImage?, Never>?
        let sync = WidgetSyncService(writer: { sink }, thumbnail: { _, _ in
            await withCheckedContinuation { continuation = $0 }
        })
        let old = Task { await sync.syncFavorites([removed]) }
        while continuation == nil { await Task.yield() }
        await sync.syncFavorites([])
        continuation?.resume(returning: nil)
        await old.value
        XCTAssertTrue(sink.favorites.isEmpty)
    }

    @MainActor
    func testConfirmationRefreshesSizesAndKeepsSelectionUntilConfirmed() async throws {
        let video = try file(service.libraryURL.appendingPathComponent("copy.mp4"), bytes: 10)
        let storage = try XCTUnwrap(service)
        var deletes = 0
        let model = LibraryStorageModel(scan: { try storage.scan() }, remove: { items in
            deletes += 1
            return storage.remove(items)
        })
        await model.refresh()
        model.selection = [video]
        try file(video, bytes: 200)
        await model.prepareRemoval(caches: false)
        let plan = try XCTUnwrap(model.plan)
        XCTAssertEqual(plan.items.count, 1)
        XCTAssertEqual(plan.bytes, 200)
        XCTAssertEqual(deletes, 0)
        model.plan = nil // Cancel confirmation: no filesystem mutation.
        XCTAssertTrue(FileManager.default.fileExists(atPath: video.path))
        await model.prepareRemoval(caches: false)
        await model.confirmRemoval(try XCTUnwrap(model.plan))
        XCTAssertEqual(deletes, 1)
        XCTAssertTrue(model.selection.isEmpty)
        XCTAssertTrue(model.scan.items.isEmpty)
    }

    @MainActor
    func testPartialFailureKeepsFailedSelectionAndReportsIt() async throws {
        let video = try file(service.libraryURL.appendingPathComponent("copy.mp4"), bytes: 10)
        let storage = try XCTUnwrap(service)
        let model = LibraryStorageModel(scan: { try storage.scan() }, remove: { storage.remove($0) })
        await model.refresh()
        model.selection = [video]
        await model.prepareRemoval(caches: false)
        let plan = try XCTUnwrap(model.plan)
        try file(video, bytes: 30)
        await model.confirmRemoval(plan)
        XCTAssertEqual(model.failures.count, 1)
        XCTAssertEqual(model.selection, [video])
        XCTAssertEqual(model.scan.totalBytes, 30)
    }

    @MainActor
    func testRepeatedConfirmationCannotStartOverlappingDeletion() async throws {
        try file(service.libraryURL.appendingPathComponent("copy.mp4"), bytes: 10)
        let snapshot = try service.scan()
        var continuation: CheckedContinuation<StorageRemovalResult, Never>?
        var calls = 0
        let model = LibraryStorageModel(scan: { snapshot }, remove: { _ in
            calls += 1
            return await withCheckedContinuation { continuation = $0 }
        })
        let plan = StorageRemovalPlan(items: snapshot.items, isCacheCleanup: false)
        let operation = Task { await model.confirmRemoval(plan) }
        while continuation == nil { await Task.yield() }
        await model.confirmRemoval(plan)
        XCTAssertEqual(calls, 1)
        continuation?.resume(returning: StorageRemovalResult())
        await operation.value
        XCTAssertFalse(model.isBusy)
    }
}

private final class StorageWidgetSink: WidgetDataWriting {
    var currentID: UUID?
    var currentWrites = 0
    var isPlaying = false
    var favorites: [SharedWidgetWallpaper] = []
    func updateCurrentWallpaper(id: UUID?, name: String?, thumbnailPath: String?) {
        currentID = id
        currentWrites += 1
    }
    func updatePlaybackState(isPlaying: Bool) { self.isPlaying = isPlaying }
    func updateFavoriteWallpapers(_ wallpapers: [SharedWidgetWallpaper]) { favorites = wallpapers }
    func saveThumbnail(data: Data, for wallpaperID: UUID) -> String? { nil }
}
