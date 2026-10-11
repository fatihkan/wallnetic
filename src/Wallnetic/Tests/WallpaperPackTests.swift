import XCTest
import AVFoundation
@testable import Wallnetic

private enum PackFixtures {
    static let bundle = Bundle(for: WallpaperPackCatalogTests.self)
    static func catalogData() throws -> Data {
        try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "wallpaper-packs-v1", withExtension: "json")))
    }
    static func catalog() throws -> WallpaperPackCatalog { try WallpaperPackCatalog.decode(catalogData()) }
    static func media(_ item: WallpaperPackItem) throws -> Data {
        try Data(contentsOf: XCTUnwrap(bundle.url(forResource: item.id, withExtension: "mp4")))
    }
    static func mutate(_ change: (inout [String: Any]) -> Void) throws -> Data {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: catalogData()) as? [String: Any])
        change(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }
    static func mutateItem(_ change: (inout [String: Any]) -> Void) throws -> Data {
        try mutate { catalog in
            var packs = catalog["packs"] as! [[String: Any]]
            var items = packs[0]["items"] as! [[String: Any]]
            change(&items[0]); packs[0]["items"] = items; catalog["packs"] = packs
        }
    }
}

final class WallpaperPackCatalogTests: XCTestCase {
    func testPublishedAndBundledCatalogsMatchAndIncludeRightsForEveryItem() throws {
        let bundled = try XCTUnwrap(Bundle(for: WallpaperPacksModel.self).url(forResource: "wallpaper-packs-v1", withExtension: "json"))
        XCTAssertEqual(try Data(contentsOf: bundled), try PackFixtures.catalogData())
        let catalog = try PackFixtures.catalog()
        XCTAssertEqual(catalog.packs.first?.items.count, 2)
        for item in catalog.packs.flatMap(\.items) {
            XCTAssertEqual(item.license, "MIT")
            XCTAssertTrue(item.attribution.contains("Copyright"))
            XCTAssertEqual(WallpaperPackCatalog.digest(try PackFixtures.media(item)), item.sha256)
        }
        let licenseURL = try XCTUnwrap(Bundle(for: WallpaperPacksModel.self).url(forResource: "pack-LICENSE-MIT", withExtension: "txt"))
        let originalLicense = try XCTUnwrap(PackFixtures.bundle.url(forResource: "LICENSE", withExtension: nil))
        XCTAssertEqual(try Data(contentsOf: licenseURL), try Data(contentsOf: originalLicense))
    }

    func testRejectsUntrustedHostsCredentialsTraversalQueriesAndMutableRefs() throws {
        let valid = try XCTUnwrap(PackFixtures.catalog().packs.first?.items.first?.url.absoluteString)
        let invalid = [valid.replacingOccurrences(of: "https:", with: "http:"),
                       valid.replacingOccurrences(of: "raw.githubusercontent.com", with: "raw.githubusercontent.com.evil.test"),
                       valid.replacingOccurrences(of: "https://", with: "https://user:password@"),
                       valid.replacingOccurrences(of: "/fatihkan/", with: "/attacker/"),
                       valid.replacingOccurrences(of: "/catalog/media/", with: "/catalog/media/../"),
                       valid.replacingOccurrences(of: "/catalog/media/", with: "/catalog%2fmedia/"),
                       valid + "?token=anything", valid + "#fragment", valid.replacingOccurrences(of: ".com/", with: ".com:443/"),
                       "https://raw.githubusercontent.com/fatihkan/wallnetic/dev/catalog/media/lagoon.mp4",
                       "file:///tmp/lagoon.mp4"]
        for value in invalid {
            XCTAssertThrowsError(try WallpaperPackCatalog.decode(PackFixtures.mutateItem { $0["url"] = value }), value)
        }
    }

    func testRejectsOversizedManifestInvalidSchemaDuplicateIDsAndUnsafeText() throws {
        XCTAssertThrowsError(try WallpaperPackCatalog.decode(Data(repeating: 0, count: WallpaperPackCatalog.maximumBytes + 1)))
        for change: (inout [String: Any]) -> Void in [
            { $0["schemaVersion"] = 2 }, { $0["revision"] = -1 },
            { $0["packs"] = Array(repeating: ($0["packs"] as! [[String: Any]])[0], count: 21) }
        ] { XCTAssertThrowsError(try WallpaperPackCatalog.decode(PackFixtures.mutate(change))) }
        for (key, value): (String, Any) in [("name", "bad\u{202E}name"), ("name", String(repeating: "a", count: 81)),
                                          ("id", "../file"), ("id", "lagoon\n"), ("bytes", 0), ("bytes", 8 * 1024 * 1024 + 1),
                                          ("license", "unknown"), ("sha256", String(repeating: "f", count: 63)),
                                          ("width", 50000), ("duration", 31), ("fps", 60), ("previewJPEG", "not an image")] {
            XCTAssertThrowsError(try WallpaperPackCatalog.decode(PackFixtures.mutateItem { $0[key] = value }), key)
        }
    }

    func testBothOriginalVideosPassRealMediaValidation() async throws {
        for item in try PackFixtures.catalog().packs[0].items {
            try await WallpaperPackMedia.validate(PackFixtures.media(item), item: item)
        }
    }

    func testPreviewPixelAndByteLimitsRejectOversizedJPEGs() throws {
        let item = try PackFixtures.catalog().packs[0].items[0]
        var jpeg = try XCTUnwrap(Data(base64Encoded: item.previewJPEG))
        let marker = try XCTUnwrap(jpeg.range(of: Data([0xff, 0xc0])) ?? jpeg.range(of: Data([0xff, 0xc2])))
        jpeg[marker.lowerBound + 7] = 0x10 // advertise 4096-pixel width
        jpeg[marker.lowerBound + 8] = 0
        XCTAssertThrowsError(try WallpaperPackCatalog.decode(PackFixtures.mutateItem { $0["previewJPEG"] = jpeg.base64EncodedString() }))
        let huge = Data(repeating: 0, count: 64 * 1024 + 1).base64EncodedString()
        XCTAssertThrowsError(try WallpaperPackCatalog.decode(PackFixtures.mutateItem { $0["previewJPEG"] = huge }))
    }

    func testTamperedTruncatedAndIncorrectlyAdvertisedMediaAreRejected() async throws {
        let item = try PackFixtures.catalog().packs[0].items[0]
        var altered = try PackFixtures.media(item)
        altered[altered.count - 1] ^= 1
        for data in [altered, Data(altered.prefix(100))] {
            do { try await WallpaperPackMedia.validate(data, item: item); XCTFail("Bad media accepted") } catch {}
        }
        let mismatch = try WallpaperPackCatalog.decode(PackFixtures.mutateItem { $0["width"] = 640 }).packs[0].items[0]
        do { try await WallpaperPackMedia.validate(PackFixtures.media(item), item: mismatch); XCTFail("Metadata mismatch accepted") } catch {}
    }

    func testExternalMP4ReferencesAndMalformedAtomsAreRejectedBeforeAVFoundation() throws {
        let item = try PackFixtures.catalog().packs[0].items[0]
        var data = try PackFixtures.media(item)
        let marker = try XCTUnwrap(data.range(of: Data("url ".utf8)))
        data[marker.upperBound + 3] = 0 // self-contained flag -> external reference
        XCTAssertThrowsError(try WallpaperPackMedia.validateReferences(data))
        XCTAssertThrowsError(try WallpaperPackMedia.validateReferences(Data([0, 0, 0, 1, 109, 111, 111, 118])))
        XCTAssertThrowsError(try WallpaperPackMedia.validateReferences(Data(data.dropLast())))
    }
}

@MainActor
final class WallpaperPacksModelTests: XCTestCase {
    private var root: URL!
    private var storage: LibraryStorage!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        storage = LibraryStorage(libraryURL: root.appendingPathComponent("Library"), framesURL: root.appendingPathComponent("Frames"),
                                 thumbnailsURL: nil, metadataURL: root.appendingPathComponent("metadata.sqlite"))
        try FileManager.default.createDirectory(at: storage.libraryURL, withIntermediateDirectories: true)
        suite = "WallpaperPackTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }
    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: root)
    }
    private func model(fetch: ((URL, Int, @escaping @Sendable (Int) async -> Void) async throws -> Data)? = nil,
                       validate: @escaping (Data, WallpaperPackItem) async throws -> Void = { try await WallpaperPackMedia.validate($0, item: $1) }) throws -> WallpaperPacksModel {
        let storage = self.storage!
        return WallpaperPacksModel(defaults: defaults, bundledData: try PackFixtures.catalogData(), fetch: fetch ?? { url, _, progress in
            let item = try XCTUnwrap(PackFixtures.catalog().packs[0].items.first { $0.url == url })
            let data = try PackFixtures.media(item)
            await progress(data.count)
            return data
        }, validate: validate, install: { data, _ in try storage.installPackData(data) },
           verify: { try storage.verifiedPackItem($0) }, remove: { storage.remove($0) })
    }
    private func receipt(for item: StorageItem, data: Data) -> PackReceipt {
        PackReceipt(packID: "soft-motion", itemID: "lagoon", sha256: WallpaperPackCatalog.digest(data), filename: item.url.lastPathComponent,
                    identity: item.identity, directoryIdentity: item.directoryIdentity)
    }

    func testOpeningOfflineCatalogNeverFetchesAndFailedRefreshKeepsIt() async throws {
        var calls = 0
        let model = try model(fetch: { _, _, _ in calls += 1; throw URLError(.notConnectedToInternet) })
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(model.catalog?.packs.count, 1)
        model.refresh(); await model.waitUntilFinished()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(model.catalog?.packs.count, 1)
        XCTAssertTrue(model.status.contains("Previous catalog kept"))
    }

    func testRefreshPersistsNewerCatalogAndRejectsRollbackOrSameRevisionMutation() async throws {
        let updated = try PackFixtures.mutate { $0["revision"] = 2; $0["packs"] = [] }
        let model = try model(fetch: { _, _, _ in updated })
        model.refresh(); await model.waitUntilFinished()
        XCTAssertEqual(model.catalog?.revision, 2)
        let restored = try self.model(fetch: { _, _, _ in try PackFixtures.catalogData() })
        XCTAssertEqual(restored.catalog?.revision, 2)
        restored.refresh(); await restored.waitUntilFinished()
        XCTAssertEqual(restored.catalog?.revision, 2)
        let collision = try self.model(fetch: { _, _, _ in try PackFixtures.mutate { $0["revision"] = 2 } })
        collision.refresh(); await collision.waitUntilFinished()
        XCTAssertEqual(collision.catalog?.packs.count, 0)
    }

    func testInvalidCacheFallsBackToBundledCatalogAndCorruptReceiptsDisableMutation() throws {
        defaults.set(Data("bad json".utf8), forKey: WallpaperPacksModel.cacheKey)
        defaults.set(Data("bad records".utf8), forKey: PackReceiptStore.key)
        let model = try model()
        XCTAssertEqual(model.catalog?.revision, 1)
        XCTAssertTrue(model.ownershipError)
        model.download(try XCTUnwrap(model.catalog?.packs.first))
        XCTAssertFalse(model.busy)
        XCTAssertTrue(try storage.scan().items.isEmpty)
        defaults.set("wrong preference type", forKey: PackReceiptStore.key)
        XCTAssertThrowsError(try PackReceiptStore(defaults: defaults).load())
    }

    func testDownloadRestartRetryAndRemovalPreserveUnrelatedImports() async throws {
        let original = storage.libraryURL.appendingPathComponent("my-personal-video.mp4")
        let data = Data("personal content".utf8)
        try data.write(to: original)
        let model = try model()
        let pack = try XCTUnwrap(model.catalog?.packs.first)
        model.download(pack); await model.waitUntilFinished()
        XCTAssertEqual(model.receipts.count, 2)
        XCTAssertEqual(model.downloadedBytes, pack.bytes)
        let restored = try self.model(fetch: { _, _, _ in XCTFail("Existing copies should not download again"); throw PackError.transfer })
        restored.download(pack); await restored.waitUntilFinished()
        XCTAssertEqual(restored.receipts.count, 2)
        XCTAssertEqual(try storage.scan().items.count, 3)
        restored.removePack(pack.id); await restored.waitUntilFinished()
        XCTAssertTrue(restored.receipts.isEmpty)
        XCTAssertEqual(try Data(contentsOf: original), data)
        XCTAssertEqual(try storage.scan().items.count, 1)
    }

    func testCancelKeepsCompletedCopyAndRetryDownloadsOnlyMissingItem() async throws {
        let waiting = expectation(description: "Second download waiting")
        var calls = 0
        let model = try model(fetch: { _, _, progress in
            calls += 1
            if calls == 2 { waiting.fulfill(); try await Task.sleep(nanoseconds: 30_000_000_000) }
            let data = try PackFixtures.media(PackFixtures.catalog().packs[0].items[0])
            await progress(data.count)
            return data
        })
        let pack = try XCTUnwrap(model.catalog?.packs.first)
        model.download(pack)
        await fulfillment(of: [waiting], timeout: 10)
        model.cancel(); await model.waitUntilFinished()
        XCTAssertEqual(model.receipts.count, 1)
        XCTAssertTrue(model.status.contains("cancelled"))
        let retry = try self.model()
        retry.download(pack); await retry.waitUntilFinished()
        XCTAssertEqual(retry.receipts.count, 2)
        XCTAssertEqual(try storage.scan().items.count, 2)
    }

    func testValidationFailureNeverInstallsAndConcurrentDownloadIsIgnored() async throws {
        var calls = 0
        let model = try model(fetch: { _, _, _ in calls += 1; return Data("untrusted content".utf8) })
        let pack = try XCTUnwrap(model.catalog?.packs.first)
        model.download(pack); model.download(pack)
        await model.waitUntilFinished()
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(model.receipts.isEmpty)
        XCTAssertTrue(try storage.scan().items.isEmpty)
    }

    func testRemovalKeepsChangedAndReplacedFilesAndForgetsMissingCopies() async throws {
        let model = try model()
        let pack = try XCTUnwrap(model.catalog?.packs.first)
        model.download(pack); await model.waitUntilFinished()
        guard model.receipts.count == 2 else { XCTFail(model.status); return }
        let first = storage.libraryURL.appendingPathComponent(model.receipts[0].filename)
        let second = storage.libraryURL.appendingPathComponent(model.receipts[1].filename)
        let replacement = Data("my new content".utf8)
        try replacement.write(to: first, options: .atomic)
        try FileManager.default.removeItem(at: second)
        model.removePack(pack.id); await model.waitUntilFinished()
        XCTAssertEqual(try Data(contentsOf: first), replacement)
        XCTAssertTrue(model.receipts.isEmpty)
        XCTAssertTrue(model.status.contains("Kept 1"))
    }

    func testSameBytesAtReplacedInodeDoNotProveOwnership() throws {
        let data = Data("test content".utf8)
        let item = try storage.installPackData(data)
        let proof = receipt(for: item, data: data)
        XCTAssertNotNil(try storage.verifiedPackItem(proof))
        try data.write(to: item.url, options: .atomic)
        XCTAssertThrowsError(try storage.verifiedPackItem(proof))
    }

    func testSymlinkLibraryAndSymlinkOwnedFileAreRejectedWithoutTouchingTargets() throws {
        let data = Data("test content".utf8)
        let item = try storage.installPackData(data)
        let proof = receipt(for: item, data: data)
        let external = root.appendingPathComponent("outside.mp4")
        try data.write(to: external)
        try FileManager.default.removeItem(at: item.url)
        try FileManager.default.createSymbolicLink(at: item.url, withDestinationURL: external)
        XCTAssertThrowsError(try storage.verifiedPackItem(proof))
        XCTAssertEqual(try Data(contentsOf: external), data)
        try FileManager.default.moveItem(at: storage.libraryURL, to: root.appendingPathComponent("Moved"))
        try FileManager.default.createSymbolicLink(at: storage.libraryURL, withDestinationURL: root.appendingPathComponent("Moved"))
        XCTAssertThrowsError(try storage.installPackData(data))
        XCTAssertThrowsError(try storage.verifiedPackItem(proof))
    }

    func testReceiptTraversalAndOversizedWritesAreRejected() throws {
        let data = Data("test content".utf8)
        let item = try storage.installPackData(data)
        let forged = PackReceipt(packID: "soft-motion", itemID: "lagoon", sha256: WallpaperPackCatalog.digest(data), filename: "../outside.mp4",
                                 identity: item.identity, directoryIdentity: item.directoryIdentity)
        XCTAssertThrowsError(try storage.verifiedPackItem(forged))
        defaults.set(try JSONEncoder().encode([forged]), forKey: PackReceiptStore.key)
        XCTAssertThrowsError(try PackReceiptStore(defaults: defaults).load())
        XCTAssertThrowsError(try storage.installPackData(Data(repeating: 0, count: WallpaperPackCatalog.maximumMediaBytes + 1)))
    }
}

private final class PackURLProtocol: URLProtocol {
    static var handler: ((URLRequest, URLProtocolClient, URLProtocol) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handler?(request, client!, self) }
    override func stopLoading() {}
}

final class WallpaperPackTransferTests: XCTestCase {
    override func tearDown() { PackURLProtocol.handler = nil }
    private func transfer() -> WallpaperPackTransfer {
        WallpaperPackTransfer(configuration: {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [PackURLProtocol.self]
            return config
        })
    }
    private func reply(status: Int = 200, data: Data, declaredSize: Int? = nil) {
        PackURLProtocol.handler = { request, client, proto in
            let headers = declaredSize.map { ["Content-Length": String($0)] }
            client.urlProtocol(proto, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(proto, didLoad: data)
            client.urlProtocolDidFinishLoading(proto)
        }
    }
    func testAcceptsBoundedResponse() async throws {
        let data = Data(repeating: 7, count: 100)
        reply(data: data, declaredSize: 100)
        let received = try await transfer().fetch(WallpaperPackCatalog.updateURL, limit: 100)
        XCTAssertEqual(received, data)
    }
    func testRejectsOversizedDeclaredAndChunkedResponsesAndHTTPFailures() async throws {
        for (status, size, declared): (Int, Int, Int?) in [(200, 1, 101), (200, 101, nil), (404, 5, nil), (302, 5, nil)] {
            reply(status: status, data: Data(repeating: 7, count: size), declaredSize: declared)
            do { _ = try await transfer().fetch(WallpaperPackCatalog.updateURL, limit: 100); XCTFail("Unsafe response accepted") } catch {}
        }
    }
    func testCancellationInterruptsStalledResponse() async throws {
        let started = expectation(description: "Request started")
        PackURLProtocol.handler = { _, _, _ in started.fulfill() }
        let transfer = transfer()
        let task = Task { try await transfer.fetch(WallpaperPackCatalog.updateURL, limit: 100) }
        await fulfillment(of: [started], timeout: 3)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled request completed") } catch {}
    }
    func testCancellationInterruptsStalledBody() async throws {
        let started = expectation(description: "Body started")
        PackURLProtocol.handler = { request, client, proto in
            client.urlProtocol(proto, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(proto, didLoad: Data([1]))
            started.fulfill()
        }
        let transfer = transfer()
        let task = Task { try await transfer.fetch(WallpaperPackCatalog.updateURL, limit: 100) }
        await fulfillment(of: [started], timeout: 3)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled body completed") } catch {}
    }
    func testRedirectDelegateNeverFollowsNewDestination() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let response = HTTPURLResponse(url: WallpaperPackCatalog.updateURL, statusCode: 302, httpVersion: nil, headerFields: nil)!
        let request = URLRequest(url: URL(string: "https://attacker.invalid/private")!)
        var called = false
        NoPackRedirects().urlSession(session, task: session.dataTask(with: WallpaperPackCatalog.updateURL), willPerformHTTPRedirection: response, newRequest: request) { request in
            called = true; XCTAssertNil(request)
        }
        XCTAssertTrue(called)
    }
}
