import Foundation
import Combine

struct StorageRemovalPlan: Identifiable {
    let id = UUID()
    let items: [StorageItem]
    let isCacheCleanup: Bool
    var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
}

@MainActor
final class LibraryStorageModel: ObservableObject {
    @Published private(set) var scan = StorageScan()
    @Published private(set) var isBusy = false
    @Published var selection = Set<URL>()
    @Published var plan: StorageRemovalPlan?
    @Published private(set) var message: String?
    @Published private(set) var failures: [String] = []

    private let scanFiles: () async throws -> StorageScan
    private let removeFiles: ([StorageItem]) async -> StorageRemovalResult

    init(scan: @escaping () async throws -> StorageScan,
         remove: @escaping ([StorageItem]) async -> StorageRemovalResult) {
        scanFiles = scan
        removeFiles = remove
    }

    convenience init(manager: WallpaperManager) {
        self.init(scan: { try await manager.scanStorage() },
                  remove: { await manager.removeStorageItems($0) })
    }

    func refresh() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        await updateScan()
    }

    /// Refresh sizes and eligibility before presenting a fixed confirmation.
    func prepareRemoval(caches: Bool) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        plan = nil
        message = nil
        guard await updateScan() else { return }
        let items = scan.items.filter {
            $0.canRemove && (caches ? $0.category == .caches : $0.category == .videos && selection.contains($0.id))
        }
        guard !items.isEmpty else {
            message = caches ? "No unused caches to clear." : "No selected copies are available to remove."
            return
        }
        plan = StorageRemovalPlan(items: items, isCacheCleanup: caches)
    }

    func confirmRemoval(_ confirmed: StorageRemovalPlan) async {
        guard !isBusy else { return }
        isBusy = true
        plan = nil
        defer { isBusy = false }
        let result = await removeFiles(confirmed.items)
        selection.subtract(result.removed.map(\.url))
        await updateScan()
        failures = result.failures + scan.failures
        let size = ByteCountFormatter.string(fromByteCount: result.removed.reduce(0) { $0 + $1.bytes }, countStyle: .file)
        message = "Removed \(result.removed.count) file(s) (\(size))."
    }

    @discardableResult
    private func updateScan() async -> Bool {
        do {
            scan = try await scanFiles()
            selection.formIntersection(scan.items.filter { $0.category == .videos && $0.canRemove }.map(\.id))
            failures = scan.failures
            return true
        } catch is CancellationError {
            return false
        } catch {
            failures = [error.localizedDescription]
            return false
        }
    }
}
