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
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    private override init() { super.init() }

    /// Start downloading a file
    @discardableResult
    func download(name: String, from url: URL, completion: @escaping (Result<URL, Error>) -> Void) -> UUID {
        var dl = Download(name: name, url: url)
        dl.status = .downloading
        let id = dl.id
        downloads.append(dl)
        activeCount += 1

        let task = session.downloadTask(with: url)
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

    /// Download and import to library
    func downloadAndImport(name: String, from url: URL) {
        download(name: name, from: url) { result in
            Task {
                switch result {
                case .success(let localURL):
                    do {
                        _ = try await WallpaperManager.shared.importVideo(from: localURL)
                        try? FileManager.default.removeItem(at: localURL)
                        NSLog("[DownloadManager] Imported: %@", name)
                    } catch {
                        NSLog("[DownloadManager] Import failed: %@", error.localizedDescription)
                    }
                case .failure(let error):
                    NSLog("[DownloadManager] Download failed: %@", error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let id = tasks.first(where: { $0.value == downloadTask })?.key else { return }

        let ext = downloadTask.originalRequest?.url?.pathExtension ?? "mp4"
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)

        do {
            try FileManager.default.moveItem(at: location, to: dest)
            if let idx = downloads.firstIndex(where: { $0.id == id }) {
                downloads[idx].status = .completed
                downloads[idx].localURL = dest
                downloads[idx].progress = 1.0
            }
            activeCount = max(0, activeCount - 1)
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

        if let idx = downloads.firstIndex(where: { $0.id == id }) {
            downloads[idx].progress = progress
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error,
              let id = tasks.first(where: { $0.value === task })?.key else { return }

        if let idx = downloads.firstIndex(where: { $0.id == id }) {
            downloads[idx].status = .failed
        }
        activeCount = max(0, activeCount - 1)
        completionHandlers[id]?(.failure(error))
        tasks.removeValue(forKey: id)
        completionHandlers.removeValue(forKey: id)
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
