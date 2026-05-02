import Foundation
import SwiftUI

/// Manages background downloads with progress tracking
class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    struct Download: Identifiable {
        let id = UUID()
        let name: String
        let url: URL
        var progress: Double = 0
        var status: Status = .waiting
        var localURL: URL?

        enum Status: String {
            case waiting = "Waiting"
            case downloading = "Downloading"
            case completed = "Completed"
            case failed = "Failed"
            case cancelled = "Cancelled"
        }
    }

    @Published var downloads: [Download] = []
    @Published var activeCount: Int = 0

    private let maxConcurrent = 3
    private var tasks: [UUID: URLSessionDownloadTask] = [:]
    private var progressHandlers: [UUID: (Double) -> Void] = [:]
    private var completionHandlers: [UUID: (Result<URL, Error>) -> Void] = [:]
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = maxConcurrent
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        return URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
    }()

    private override init() { super.init() }

    /// Start downloading a file
    @discardableResult
    func download(name: String, from url: URL, completion: @escaping (Result<URL, Error>) -> Void) -> UUID {
        download(name: name, request: URLRequest(url: url), completion: completion)
    }

    /// Start downloading with a custom request (e.g. with cookies)
    @discardableResult
    func download(name: String, request: URLRequest, completion: @escaping (Result<URL, Error>) -> Void) -> UUID {
        var dl = Download(name: name, url: request.url ?? URL(string: "about:blank")!)
        dl.status = .downloading
        let id = dl.id
        downloads.append(dl)
        activeCount += 1

        let task = session.downloadTask(with: request)
        tasks[id] = task
        completionHandlers[id] = completion

        task.resume()
        return id
    }

    /// Cancel a download
    func cancel(id: UUID) {
        tasks[id]?.cancel()
        tasks.removeValue(forKey: id)
        if let idx = downloads.firstIndex(where: { $0.id == id }) {
            downloads[idx].status = .cancelled
            activeCount = max(0, activeCount - 1)
        }
    }

    // MARK: - External download tracking (for WKDownload etc.)

    /// Register an externally managed download so it appears in the UI
    func trackDownload(name: String) -> UUID {
        var dl = Download(name: name, url: URL(string: "about:blank")!)
        dl.status = .downloading
        let id = dl.id
        downloads.append(dl)
        activeCount += 1
        return id
    }

    /// Update progress for a tracked download
    func updateProgress(id: UUID, progress: Double) {
        if let idx = downloads.firstIndex(where: { $0.id == id }) {
            downloads[idx].progress = progress
        }
    }

    /// Mark a tracked download as completed (auto-removes from UI after 3s)
    func completeDownload(id: UUID) {
        if let idx = downloads.firstIndex(where: { $0.id == id }) {
            downloads[idx].status = .completed
            downloads[idx].progress = 1.0
        }
        activeCount = max(0, activeCount - 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.downloads.removeAll { $0.id == id }
        }
    }

    /// Mark a tracked download as failed (auto-removes from UI after 5s)
    func failDownload(id: UUID) {
        if let idx = downloads.firstIndex(where: { $0.id == id }) {
            downloads[idx].status = .failed
        }
        activeCount = max(0, activeCount - 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.downloads.removeAll { $0.id == id }
        }
    }

    /// Download and import to library (handles mp4, zip+mlw, and mlw files)
    func downloadAndImport(name: String, from url: URL) {
        downloadAndImport(name: name, request: URLRequest(url: url))
    }

    /// Download with custom request and import to library
    func downloadAndImport(name: String, request: URLRequest) {
        download(name: name, request: request) { result in
            Task {
                switch result {
                case .success(let localURL):
                    do {
                        let importURL = try Self.processDownload(at: localURL, name: name)
                        _ = try await WallpaperManager.shared.importVideo(from: importURL)
                        try? FileManager.default.removeItem(at: importURL)
                        if importURL != localURL {
                            try? FileManager.default.removeItem(at: localURL)
                        }
                        Log.download.info("Imported: \(name, privacy: .public)")
                    } catch {
                        Log.download.error("Import failed: \(error.localizedDescription, privacy: .public)")
                    }
                case .failure(let error):
                    Log.download.error("Download failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Process a downloaded file — decrypt MLW/ZIP if needed, return path to importable MP4
    private static func processDownload(at localURL: URL, name: String) throws -> URL {
        let ext = localURL.pathExtension.lowercased()

        // ZIP file (likely from mylivewallpapers.com) — extract .mlw and decrypt
        if ext == "zip" || isZIPFile(at: localURL) {
            Log.download.info("Processing ZIP for MLW content: \(name, privacy: .public)")
            let mp4URL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            try MLWDecryptor.decryptFromZIP(fileAt: localURL, to: mp4URL)
            return mp4URL
        }

        // Direct .mlw file
        if ext == "mlw" || isMLWFile(at: localURL) {
            Log.download.info("Processing MLW file: \(name, privacy: .public)")
            let mp4URL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            try MLWDecryptor.decrypt(fileAt: localURL, to: mp4URL)
            return mp4URL
        }

        // Standard video file — pass through
        return localURL
    }

    /// Check if file starts with ZIP magic bytes (PK\x03\x04)
    private static func isZIPFile(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let header = handle.readData(ofLength: 4)
        return header.count >= 4 && header[0] == 0x50 && header[1] == 0x4b
            && header[2] == 0x03 && header[3] == 0x04
    }

    /// Check if file starts with MLW magic bytes
    private static func isMLWFile(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let header = handle.readData(ofLength: 9)
        return header == Data("MLW.VIDEO".utf8) || header == Data("MLW.DEPTH".utf8)
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let id = tasks.first(where: { $0.value == downloadTask })?.key else { return }

        let ext = Self.resolveExtension(for: downloadTask)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)

        do {
            try FileManager.default.moveItem(at: location, to: dest)
            DispatchQueue.main.async { [self] in
                if let idx = downloads.firstIndex(where: { $0.id == id }) {
                    downloads[idx].status = .completed
                    downloads[idx].localURL = dest
                    downloads[idx].progress = 1.0
                }
                activeCount = max(0, activeCount - 1)
            }
            completionHandlers[id]?(.success(dest))
        } catch {
            completionHandlers[id]?(.failure(error))
        }

        tasks.removeValue(forKey: id)
        completionHandlers.removeValue(forKey: id)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let id = tasks.first(where: { $0.value == downloadTask })?.key else { return }

        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0

        DispatchQueue.main.async { [self] in
            if let idx = downloads.firstIndex(where: { $0.id == id }) {
                downloads[idx].progress = progress
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error,
              let id = tasks.first(where: { $0.value === task })?.key else { return }

        DispatchQueue.main.async { [self] in
            if let idx = downloads.firstIndex(where: { $0.id == id }) {
                downloads[idx].status = .failed
            }
            activeCount = max(0, activeCount - 1)
        }
        completionHandlers[id]?(.failure(error))
        tasks.removeValue(forKey: id)
        completionHandlers.removeValue(forKey: id)
    }

    /// Determine the correct file extension from response headers or URL
    private static func resolveExtension(for task: URLSessionDownloadTask) -> String {
        // Try Content-Disposition header first
        if let response = task.response as? HTTPURLResponse,
           let disposition = response.value(forHTTPHeaderField: "Content-Disposition"),
           let fileName = disposition.components(separatedBy: "filename=").last?
               .trimmingCharacters(in: CharacterSet(charactersIn: "\" ")),
           !fileName.isEmpty {
            let ext = (fileName as NSString).pathExtension
            if !ext.isEmpty { return ext }
        }

        // Try MIME type
        if let mimeType = task.response?.mimeType {
            switch mimeType {
            case "application/zip", "application/x-zip-compressed": return "zip"
            case "video/mp4": return "mp4"
            case "video/quicktime": return "mov"
            case "video/webm": return "webm"
            default: break
            }
        }

        // Fall back to URL extension
        let ext = task.originalRequest?.url?.pathExtension ?? ""
        return ext.isEmpty ? "mp4" : ext
    }
}

// MARK: - Source Errors

enum SourceError: LocalizedError {
    case noAPIKey(String)
    case parseFailed(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey(let name): return "\(name) API key not configured"
        case .parseFailed(let msg): return "Parse error: \(msg)"
        case .networkError(let msg): return "Network error: \(msg)"
        }
    }
}
