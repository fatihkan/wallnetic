import Foundation
import os.log

/// Handles all file-system operations for the wallpaper library:
/// loading, importing, removing, duplicate detection, directory watching.
final class WallpaperLibrary {
    static let shared = WallpaperLibrary()

    private let fileManager = FileManager.default

    /// Resolved once — avoids FileManager I/O on every call.
    lazy var libraryURL: URL = {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Wallnetic/Library", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }()

    private var fileWatcher: DispatchSourceFileSystemObject?

    private init() {}

    // MARK: - Load

    /// Scans the library directory and returns raw wallpaper objects.
    func loadAll(favoritePaths: Set<String>) -> [Wallpaper] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: libraryURL,
            includingPropertiesForKeys: [.contentTypeKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return contents.compactMap { url in
            guard isVideoFile(url) else { return nil }
            return Wallpaper(url: url, isFavorite: favoritePaths.contains(url.path))
        }
    }

    // MARK: - Import

    /// Imports a video file into the library. Returns the new library-local URL.
    func importFile(from sourceURL: URL, existingWallpapers: [Wallpaper]) async throws -> URL {
        // Duplicate detection
        let sourceSize = (try? fileManager.attributesOfItem(atPath: sourceURL.path))?[.size] as? Int64 ?? 0
        let sourceName = sourceURL.deletingPathExtension().lastPathComponent
        if let dup = existingWallpapers.first(where: { $0.fileSize == sourceSize && $0.name == sourceName }) {
            throw WallpaperImportError.duplicate(dup.name)
        }

        // Convert non-native formats to MP4
        var importURL = sourceURL
        if VideoFormatConverter.shared.needsConversion(sourceURL) {
            importURL = try await VideoFormatConverter.shared.convertToMP4(source: sourceURL)
        }

        let originalName = sourceURL.deletingPathExtension().lastPathComponent
        let fileName = originalName + ".mp4"
        let destURL = libraryURL.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: destURL.path) {
            let uniqueName = UUID().uuidString + "_" + fileName
            let uniqueURL = libraryURL.appendingPathComponent(uniqueName)
            try fileManager.copyItem(at: importURL, to: uniqueURL)
            return uniqueURL
        } else {
            try fileManager.copyItem(at: importURL, to: destURL)
            return destURL
        }
    }

    // MARK: - Remove

    func removeFile(at url: URL) {
        try? fileManager.removeItem(at: url)
    }

    // MARK: - File Watching

    /// Starts monitoring the library folder. Calls `onChange` on the main queue.
    func startWatching(onChange: @escaping () -> Void) {
        let fd = open(libraryURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { onChange() }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileWatcher = source
    }

    func stopWatching() {
        fileWatcher?.cancel()
        fileWatcher = nil
    }

    // MARK: - Helpers

    func isVideoFile(_ url: URL) -> Bool {
        let videoExtensions = ["mp4", "mov", "m4v", "hevc"]
        return videoExtensions.contains(url.pathExtension.lowercased())
    }
}
