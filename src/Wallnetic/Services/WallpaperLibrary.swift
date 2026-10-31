import Foundation
import os.log

/// Handles all file-system operations for the wallpaper library:
/// loading, importing, removing, duplicate detection, directory watching.
final class WallpaperLibrary {
    static let shared = WallpaperLibrary()

    private let fileManager = FileManager.default
    private let directory: URL?

    /// Resolved once — avoids FileManager I/O on every call.
    lazy var libraryURL: URL = {
        let dir = directory ?? applicationSupportURL().appendingPathComponent("Wallnetic/Library", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }()

    private var fileWatcher: DispatchSourceFileSystemObject?

    init(directory: URL? = nil) {
        self.directory = directory
    }

    // MARK: - Load

    /// Scans the library directory and returns raw wallpaper objects.
    func loadAll(favoritePaths: Set<String>, existingIDs: [String: UUID] = [:]) -> [Wallpaper] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: libraryURL,
            includingPropertiesForKeys: [.contentTypeKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return contents.compactMap { url in
            guard isVideoFile(url) else { return nil }
            return Wallpaper(url: url, isFavorite: favoritePaths.contains(url.path), id: existingIDs[url.path] ?? UUID())
        }
    }

    // MARK: - Import

    /// Imports a video file into the library. Returns the new library-local URL.
    func importFile(from sourceURL: URL, existingWallpapers: [Wallpaper], preferredName: String? = nil) async throws -> URL {
        guard sourceURL.isFileURL,
              VideoFormatConverter.allSupportedFormats.contains(sourceURL.pathExtension.lowercased()) else {
            throw WallpaperImportError.unsupportedFile
        }
        let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { throw WallpaperImportError.unsupportedFile }

        let preferredStem = Self.filenameStem(for: preferredName)

        // Duplicate detection for ordinary local imports by filename + size. A
        // download title is not an identity: different downloads can share it.
        // Local matching still uses the on-disk name rather than a user rename.
        let sourceSize = (try? fileManager.attributesOfItem(atPath: sourceURL.path))?[.size] as? Int64 ?? 0
        let sourceFilename = sourceURL.deletingPathExtension().lastPathComponent
        if preferredStem == nil, let dup = existingWallpapers.first(where: {
            $0.fileSize == sourceSize
            && $0.url.deletingPathExtension().lastPathComponent == sourceFilename
        }) {
            throw WallpaperImportError.duplicate(dup.name)
        }

        // Convert non-native formats to MP4
        var importURL = sourceURL
        if VideoFormatConverter.shared.needsConversion(sourceURL) {
            importURL = try await VideoFormatConverter.shared.convertToMP4(source: sourceURL)
        }
        defer {
            if importURL != sourceURL {
                try? fileManager.removeItem(at: importURL)
            }
        }

        if let preferredStem {
            // FileManager's copy refuses existing destinations. Retry a name
            // collision with a readable stem plus UUID; never replace a file,
            // directory or symlink, and never derive the extension from a title.
            let ext = importURL.pathExtension.lowercased()
            let destination = libraryURL.appendingPathComponent(preferredStem + "." + ext)
            do {
                try fileManager.copyItem(at: importURL, to: destination)
                return destination
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                let uniqueName = preferredStem + " (" + UUID().uuidString + ")." + ext
                let uniqueURL = libraryURL.appendingPathComponent(uniqueName)
                try fileManager.copyItem(at: importURL, to: uniqueURL)
                return uniqueURL
            }
        }

        let originalName = sourceURL.deletingPathExtension().lastPathComponent
        let fileName = originalName + "." + importURL.pathExtension.lowercased()
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

    /// Derive one bounded filename component; the full title remains metadata.
    /// Reserve room for the collision suffix and the trusted media extension.
    private static func filenameStem(for title: String?) -> String? {
        guard let title = WallpaperMetadataStore.normalizedImportedTitle(title) else { return nil }
        let reserved = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let replaced = title.components(separatedBy: reserved).joined(separator: " ")
        let trimmed = replaced.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        var stem = ""
        var bytes = 0
        for character in trimmed {
            let text = String(character)
            // Account for decomposed Unicode as well as the input encoding.
            let count = max(text.utf8.count, text.decomposedStringWithCanonicalMapping.utf8.count)
            guard bytes + count <= 180 else { break }
            stem.append(character)
            bytes += count
        }
        stem = stem.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return stem.isEmpty ? nil : stem
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
