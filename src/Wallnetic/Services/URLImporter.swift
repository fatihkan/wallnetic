import Foundation
import AppKit

/// Downloads videos from URLs for import
class URLImporter: ObservableObject {
    static let shared = URLImporter()

    @Published var isDownloading = false
    @Published var progress: Double = 0
    @Published var statusMessage = ""
    @Published var error: String?

    private var downloadTask: URLSessionDownloadTask?

    private init() {}

    /// Checks if a URL points to a downloadable video
    func isVideoURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        let videoExtensions = ["mp4", "mov", "m4v", "webm", "gif"]
        return videoExtensions.contains(url.pathExtension.lowercased())
    }

    /// Downloads a video from URL and imports it
    func downloadAndImport(from urlString: String) async throws -> URL {
        guard let url = URL(string: urlString) else {
            throw URLImportError.invalidURL
        }

        await MainActor.run {
            isDownloading = true
            progress = 0
            statusMessage = "Connecting..."
            error = nil
        }

        // Create download request
        var request = URLRequest(url: url)
        request.timeoutInterval = 120

        let delegate = DownloadProgressDelegate { [weak self] prog in
            Task { @MainActor in
                self?.progress = prog
                self?.statusMessage = "Downloading... \(Int(prog * 100))%"
            }
        }

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let downloadTask = session.downloadTask(with: request)
        self.downloadTask = downloadTask

        return try await withCheckedThrowingContinuation { continuation in
            delegate.completion = { result in
                Task { @MainActor [weak self] in
                    self?.isDownloading = false

                    switch result {
                    case .success(let tempURL):
                        // Move to a stable temp location with proper extension
                        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
                        let stableURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)
                            .appendingPathExtension(ext)

                        do {
                            try FileManager.default.moveItem(at: tempURL, to: stableURL)
                            self?.statusMessage = "Download complete"
                            continuation.resume(returning: stableURL)
                        } catch {
                            self?.error = error.localizedDescription
                            continuation.resume(throwing: error)
                        }

                    case .failure(let error):
                        self?.error = error.localizedDescription
                        continuation.resume(throwing: error)
                    }
                }
            }

            downloadTask.resume()
        }
    }

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        statusMessage = "Cancelled"
    }
}

// MARK: - Download Delegate

private class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: (Double) -> Void
    var completion: ((Result<URL, Error>) -> Void)?

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        completion?(.success(location))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            completion?(.failure(error))
        }
    }
}

// MARK: - Errors

enum URLImportError: LocalizedError {
    case invalidURL
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .downloadFailed: return "Download failed"
        }
    }
}
