import Foundation
import AppKit

/// Downloads videos from URLs for import
@MainActor
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

        isDownloading = true
        progress = 0
        statusMessage = "Connecting..."
        error = nil

        // Use URLSession.shared.download for simpler concurrency
        var request = URLRequest(url: url)
        request.timeoutInterval = 120

        do {
            let (tempURL, response) = try await URLSession.shared.download(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                isDownloading = false
                throw URLImportError.downloadFailed
            }

            // Move to stable location
            let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
            let stableURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)

            try FileManager.default.moveItem(at: tempURL, to: stableURL)

            isDownloading = false
            statusMessage = "Download complete"
            progress = 1.0
            return stableURL

        } catch {
            isDownloading = false
            self.error = error.localizedDescription
            statusMessage = "Failed"
            throw error
        }
    }

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        statusMessage = "Cancelled"
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
