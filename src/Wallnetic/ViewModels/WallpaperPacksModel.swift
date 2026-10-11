import Foundation

struct PackReceipt: Codable, Equatable, Sendable {
    let packID: String
    let itemID: String
    let sha256: String
    let filename: String
    let identity: StorageFileIdentity
    let directoryIdentity: StorageFileIdentity

    var isValid: Bool {
        WallpaperPackCatalog.validID(packID) && WallpaperPackCatalog.validID(itemID) &&
            sha256.range(of: "^[a-f0-9]{64}\\z", options: .regularExpression) != nil &&
            filename.hasPrefix("pack-") && filename.hasSuffix(".mp4") && filename.count == 45 &&
            UUID(uuidString: String(filename.dropFirst(5).dropLast(4))) != nil &&
            identity.size > 0 && identity.size <= WallpaperPackCatalog.maximumMediaBytes
    }
}

/// Persisted as small bounded data, never as catalog-supplied paths. A damaged
/// ledger disables pack mutations instead of guessing which files we own.
@MainActor
final class PackReceiptStore {
    static let key = "wallpaperPackReceipts.v1"
    private let defaults: UserDefaults
    init(defaults: UserDefaults) { self.defaults = defaults }
    func load() throws -> [PackReceipt] {
        guard let value = defaults.object(forKey: Self.key) else { return [] }
        guard let data = value as? Data, data.count <= 128 * 1024,
              let receipts = try? JSONDecoder().decode([PackReceipt].self, from: data),
              receipts.count <= 80, receipts.allSatisfy(\.isValid),
              Set(receipts.map(\.filename)).count == receipts.count else { throw PackError.receipts }
        return receipts
    }
    func save(_ receipts: [PackReceipt]) throws {
        guard receipts.count <= 80, receipts.allSatisfy(\.isValid) else { throw PackError.receipts }
        let data = try JSONEncoder().encode(receipts)
        guard data.count <= 128 * 1024 else { throw PackError.receipts }
        defaults.set(data, forKey: Self.key)
    }
}

@MainActor
final class WallpaperPacksModel: ObservableObject {
    static let shared = WallpaperPacksModel()
    static let cacheKey = "wallpaperPackCatalog.v1"
    @Published private(set) var catalog: WallpaperPackCatalog?
    @Published private(set) var receipts: [PackReceipt] = []
    @Published private(set) var busy = false
    @Published private(set) var activePackID: String?
    @Published private(set) var downloadedBytes = 0
    @Published private(set) var status = "Previews are available offline. Download only the packs you want."
    @Published private(set) var catalogSource = "Included catalog"
    @Published private(set) var ownershipError = false
    @Published private(set) var isRemoving = false
    private let defaults: UserDefaults
    private let receiptStore: PackReceiptStore
    private let fetch: (URL, Int, @escaping @Sendable (Int) async -> Void) async throws -> Data
    private let validate: (Data, WallpaperPackItem) async throws -> Void
    private let install: (Data, String) async throws -> StorageItem
    private let verify: (PackReceipt) async throws -> StorageItem?
    private let remove: ([StorageItem]) async -> StorageRemovalResult
    private var task: Task<Void, Never>?

    init(defaults: UserDefaults = .standard,
         bundledData: Data? = nil,
         fetch: @escaping (URL, Int, @escaping @Sendable (Int) async -> Void) async throws -> Data = {
             try await WallpaperPackTransfer().fetch($0, limit: $1, progress: $2)
         },
         validate: @escaping (Data, WallpaperPackItem) async throws -> Void = { try await WallpaperPackMedia.validate($0, item: $1) },
         install: @escaping (Data, String) async throws -> StorageItem = { try await WallpaperManager.shared.importPackData($0, name: $1) },
         verify: @escaping (PackReceipt) async throws -> StorageItem? = { try await WallpaperManager.shared.verifiedPackItem($0) },
         remove: @escaping ([StorageItem]) async -> StorageRemovalResult = { await WallpaperManager.shared.removeStorageItems($0) }) {
        self.defaults = defaults
        self.receiptStore = PackReceiptStore(defaults: defaults)
        self.fetch = fetch
        self.validate = validate
        self.install = install
        self.verify = verify
        self.remove = remove
        let bundle = Bundle(for: WallpaperPacksModel.self)
        let bundled = bundledData ?? bundle.url(forResource: "wallpaper-packs-v1", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
        catalog = bundled.flatMap { try? WallpaperPackCatalog.decode($0) }
        if let cached = defaults.data(forKey: Self.cacheKey), let decoded = try? WallpaperPackCatalog.decode(cached),
           decoded.revision >= (catalog?.revision ?? 0) {
            catalog = decoded
            catalogSource = "Saved catalog · revision \(decoded.revision)"
        }
        do { receipts = try receiptStore.load() }
        catch { ownershipError = true; status = error.localizedDescription }
        if catalog == nil { status = "No catalog is available. Your local library still works. Try Refresh Catalog." }
    }

    var installedPackIDs: [String] { Array(Set(receipts.map(\.packID))).sorted() }
    func trackedCount(_ packID: String) -> Int { receipts.filter { $0.packID == packID }.count }

    func refresh() {
        guard !busy else { return }
        start(packID: nil)
        status = "Refreshing catalog…"
        task = Task {
            defer { finish() }
            do {
                let data = try await fetch(WallpaperPackCatalog.updateURL, WallpaperPackCatalog.maximumBytes, { _ in })
                let updated = try WallpaperPackCatalog.decode(data)
                guard updated.revision >= (catalog?.revision ?? 0),
                      updated.revision != catalog?.revision || updated == catalog else { throw PackError.invalidCatalog }
                try Task.checkCancellation()
                defaults.set(data, forKey: Self.cacheKey)
                catalog = updated
                catalogSource = "Saved catalog · revision \(updated.revision)"
                status = "Catalog is up to date. Existing downloads are unchanged."
            } catch { status = Task.isCancelled ? "Refresh cancelled. Previous catalog kept." : "Refresh failed. Previous catalog kept. \(error.localizedDescription)" }
        }
    }

    func download(_ pack: WallpaperPack) {
        guard !busy, !ownershipError, catalog?.packs.contains(pack) == true else { return }
        start(packID: pack.id)
        status = "Downloading \(pack.name)…"
        task = Task {
            defer { finish() }
            do {
                for item in pack.items {
                    try Task.checkCancellation()
                    let matches = receipts.filter { $0.packID == pack.id && $0.itemID == item.id && $0.sha256 == item.sha256 }
                    var present = false
                    for receipt in matches {
                        if (try? await verify(receipt)) != nil { present = true; break }
                        // Missing/edited copies are never reclaimed. Forget their
                        // receipt only; the user's library file remains untouched.
                        try persist(receipts.filter { $0 != receipt })
                    }
                    if present { downloadedBytes += item.bytes; continue }
                    guard receipts.count < 80 else { throw PackError.receipts }
                    let base = downloadedBytes
                    let data = try await fetch(item.url, item.bytes) { [weak self] bytes in
                        await self?.setProgress(base + min(bytes, item.bytes))
                    }
                    try await validate(data, item)
                    try Task.checkCancellation()
                    let storageItem = try await install(data, item.name)
                    let receipt = PackReceipt(packID: pack.id, itemID: item.id, sha256: item.sha256,
                                              filename: storageItem.url.lastPathComponent,
                                              identity: storageItem.identity, directoryIdentity: storageItem.directoryIdentity)
                    // Once installation starts, record it even if cancellation
                    // arrives during the atomic write. Retry reuses this copy.
                    do { try persist(receipts + [receipt]) }
                    catch { _ = await remove([storageItem]); throw error }
                    downloadedBytes = base + item.bytes
                }
                try Task.checkCancellation()
                status = "\(pack.name) is in your library. Choose a wallpaper to play it."
            } catch {
                status = Task.isCancelled ? "Download cancelled. Completed copies stay in your library; Download / Retry continues safely." : "Download stopped. Completed copies were kept. \(error.localizedDescription) Use Download / Retry."
            }
        }
    }

    func removePack(_ packID: String) {
        guard !busy, !ownershipError else { return }
        start(packID: packID)
        isRemoving = true
        status = "Checking downloaded copies…"
        task = Task {
            defer { finish() }
            var removable: [StorageItem] = [], forgotten = Set<String>(), protected = 0
            do {
                for receipt in receipts where receipt.packID == packID {
                    do {
                        if let item = try await verify(receipt) { removable.append(item) }
                        else { forgotten.insert(receipt.filename) }
                    } catch {
                        // Do not retry deletion of an altered file in the future.
                        // Relinquish it as ordinary user content.
                        protected += 1
                        forgotten.insert(receipt.filename)
                    }
                }
                let result = await remove(removable)
                forgotten.formUnion(result.removed.map { $0.url.lastPathComponent })
                try persist(receipts.filter { !forgotten.contains($0.filename) })
                status = "Removed \(result.removed.count) downloaded copies."
                if protected > 0 { status += " Kept \(protected) changed or unavailable files in your library." }
                if !result.failures.isEmpty { status += " Some copies could not be removed; retry or use Library Storage." }
            } catch { status = error.localizedDescription }
        }
    }

    func cancel() { if !isRemoving { task?.cancel() } }
    // Also allows deterministic waiting in isolated model tests.
    func waitUntilFinished() async { await task?.value }
    private func setProgress(_ bytes: Int) { downloadedBytes = bytes }
    private func start(packID: String?) { busy = true; activePackID = packID; downloadedBytes = 0 }
    private func finish() { busy = false; activePackID = nil; isRemoving = false; task = nil }
    private func persist(_ updated: [PackReceipt]) throws { try receiptStore.save(updated); receipts = updated }
}
