import Foundation
import Darwin

enum StorageCategory: String, CaseIterable, Sendable {
    case videos = "Library videos"
    case generated = "Generated still images"
    case caches = "Caches"
}

struct StorageFileIdentity: Equatable, Sendable {
    let device: Int32
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64

    init(_ info: stat) {
        device = info.st_dev
        inode = info.st_ino
        size = info.st_size
        modifiedSeconds = Int64(info.st_mtimespec.tv_sec)
        modifiedNanoseconds = Int64(info.st_mtimespec.tv_nsec)
    }
}

struct StorageItem: Identifiable, Sendable {
    var id: URL { url }
    let url: URL
    let category: StorageCategory
    var canRemove: Bool
    let identity: StorageFileIdentity
    let directoryIdentity: StorageFileIdentity
    var bytes: Int64 { identity.size }
}

struct StorageScan: Sendable {
    var items: [StorageItem] = []
    var failures: [String] = []
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    func bytes(in category: StorageCategory) -> Int64 {
        items.filter { $0.category == category }.reduce(0) { $0 + $1.bytes }
    }
}

struct StorageRemovalResult: Sendable {
    var removed: [StorageItem] = []
    var failures: [String] = []
}

/// Derive reference updates exclusively from successful unlinks, by path. The
/// current wallpaper may predate a rescan and therefore have a different UUID.
struct LibraryRemovalState {
    let urls: Set<URL>
    let paths: Set<String>
    let ids: Set<UUID>
    let wallpapers: [Wallpaper]
    let current: Wallpaper?
    let screenAssignments: [String: UUID]

    init(result: StorageRemovalResult, wallpapers: [Wallpaper], current: Wallpaper?, screenAssignments: [String: UUID]) {
        let urls = Set(result.removed.filter { $0.category == .videos }.map(\.url))
        self.urls = urls
        paths = Set(urls.map(\.path))
        var ids = Set(wallpapers.filter { urls.contains($0.url) }.map(\.id))
        if let current, urls.contains(current.url) { ids.insert(current.id) }
        self.ids = ids
        self.wallpapers = wallpapers.filter { !urls.contains($0.url) }
        self.current = current.flatMap { urls.contains($0.url) ? nil : $0 }
        self.screenAssignments = screenAssignments.filter { !ids.contains($0.value) }
    }
}

enum StorageError: LocalizedError {
    case unsafeFile, changedFile
    var errorDescription: String? {
        switch self {
        case .unsafeFile: return "This is not a removable app-managed file."
        case .changedFile: return "The file or its folder changed. Refresh and select it again."
        }
    }
}

/// Only direct regular files in explicitly owned directories are eligible.
/// Descriptor-relative unlink never follows a symlink or recursively removes a directory.
/// This type has no UI state; scans and deletions run on a background executor.
struct LibraryStorage: Sendable {
    let libraryURL: URL
    let framesURL: URL
    let thumbnailsURL: URL?
    let metadataURL: URL
    private let directoryAnchors: [String: URL]

    init(libraryURL: URL, framesURL: URL, thumbnailsURL: URL?, metadataURL: URL) {
        // Resolve platform aliases such as /var once, but never resolve the owned
        // directory itself: a Library/Thumbnails symlink must be rejected.
        func anchored(_ url: URL) -> URL {
            var parent = url.deletingLastPathComponent()
            var missing: [String] = []
            // Foundation normalizes /private/var back to the /var symlink.
            // realpath preserves the physical path needed by O_NOFOLLOW.
            while true {
                if let resolved = realpath(parent.path, nil) {
                    var result = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
                    free(resolved)
                    for component in missing.reversed() { result.appendPathComponent(component) }
                    return result.appendingPathComponent(url.lastPathComponent)
                }
                guard parent.path != "/" else { return url }
                missing.append(parent.lastPathComponent)
                parent.deleteLastPathComponent()
            }
        }
        // Keep public URLs identical to the library/assignment URLs. macOS
        // sandbox container paths may contain aliases; only descriptor traversal
        // uses the physical anchors, otherwise successful removal could miss
        // the logical path stored in playlists and display assignments.
        self.libraryURL = libraryURL
        self.framesURL = framesURL
        self.thumbnailsURL = thumbnailsURL
        self.metadataURL = metadataURL
        var roots = [libraryURL, framesURL, metadataURL.deletingLastPathComponent()]
        if let thumbnailsURL { roots.append(thumbnailsURL) }
        self.directoryAnchors = Dictionary(roots.map { ($0.path, anchored($0)) }, uniquingKeysWith: { first, _ in first })
    }

    private var directories: [(URL, StorageCategory)] {
        var result: [(URL, StorageCategory)] = [(libraryURL, .videos), (framesURL, .generated)]
        if let thumbnailsURL { result.append((thumbnailsURL, .caches)) }
        result.append((metadataURL.deletingLastPathComponent(), .caches))
        return result
    }

    func scan(protectedThumbnailNames: Set<String> = []) throws -> StorageScan {
        var result = StorageScan()
        for (directory, category) in directories {
            try Task.checkCancellation()
            do {
                let fd = try openDirectory(directory)
                defer { close(fd) }
                var directoryInfo = stat()
                guard fstat(fd, &directoryInfo) == 0 else { throw posixError() }
                let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                for name in names where accepts(name, in: directory) {
                    try Task.checkCancellation()
                    do {
                        let info = try regularFile(name, in: fd)
                        let removable = category == .videos ||
                            (directory == thumbnailsURL && !protectedThumbnailNames.contains(name))
                        result.items.append(StorageItem(
                            url: directory.appendingPathComponent(name), category: category,
                            canRemove: removable, identity: StorageFileIdentity(info),
                            directoryIdentity: StorageFileIdentity(directoryInfo)))
                    } catch {
                        result.failures.append("\(name): \(error.localizedDescription)")
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) {
                // An unused app-owned directory need not exist yet.
            } catch {
                result.failures.append("\(directory.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return result
    }

    func remove(_ items: [StorageItem], protectedThumbnailNames: Set<String> = []) -> StorageRemovalResult {
        var result = StorageRemovalResult()
        var seen = Set<URL>()
        for item in items where seen.insert(item.url).inserted {
            do {
                try Task.checkCancellation()
                let directory = item.url.deletingLastPathComponent()
                let name = item.url.lastPathComponent
                guard item.canRemove,
                      (item.category == .videos && directory.path == libraryURL.path) ||
                        (item.category == .caches && directory.path == thumbnailsURL?.path && !protectedThumbnailNames.contains(name)),
                      accepts(name, in: directory) else { throw StorageError.unsafeFile }
                let fd = try openDirectory(directory)
                defer { close(fd) }
                var info = stat()
                guard fstat(fd, &info) == 0 else { throw posixError() }
                let identity = StorageFileIdentity(info)
                guard identity.device == item.directoryIdentity.device,
                      identity.inode == item.directoryIdentity.inode,
                      StorageFileIdentity(try regularFile(name, in: fd)) == item.identity else {
                    throw StorageError.changedFile
                }
                guard unlinkat(fd, name, 0) == 0 else { throw posixError() }
                result.removed.append(item)
            } catch {
                result.failures.append("\(item.url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return result
    }

    private func accepts(_ name: String, in directory: URL) -> Bool {
        guard !name.hasPrefix("."), !name.contains("/"), !name.contains("\0") else { return false }
        if directory.path == libraryURL.path {
            return ["mp4", "mov", "m4v", "hevc"].contains((name as NSString).pathExtension.lowercased())
        }
        if directory.path == framesURL.path {
            return name.range(of: "^frame-[a-f0-9]{16}\\.jpg$", options: .regularExpression) != nil
        }
        if directory.path == thumbnailsURL?.path {
            return (name as NSString).pathExtension == "jpg" &&
                UUID(uuidString: (name as NSString).deletingPathExtension) != nil
        }
        return [metadataURL.lastPathComponent, metadataURL.lastPathComponent + "-wal",
                metadataURL.lastPathComponent + "-shm"].contains(name)
    }

    private func regularFile(_ name: String, in fd: Int32) throws -> stat {
        var info = stat()
        guard fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw posixError() }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw StorageError.unsafeFile }
        return info
    }

    private func openDirectory(_ url: URL) throws -> Int32 {
        guard url.isFileURL, let anchor = directoryAnchors[url.path] else { throw StorageError.unsafeFile }
        guard let resolved = realpath(url.path, nil) else { throw posixError() }
        let currentPath = String(cString: resolved)
        free(resolved)
        guard currentPath == anchor.path else { throw StorageError.changedFile }
        // Ancestors are used only for relative lookup, never enumeration. Asking
        // to read their contents is unnecessary outside the app's sandbox scope.
        var fd = open("/", O_EVTONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw posixError() }
        for component in anchor.pathComponents.dropFirst() {
            let next = openat(fd, component, O_EVTONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            let failure = errno
            close(fd)
            guard next >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure)) }
            fd = next
        }
        return fd
    }

    private func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
