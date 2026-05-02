import SwiftUI
import WebKit

// MARK: - WebView Wrapper

struct WebViewWrapper: NSViewRepresentable {
    let urlString: String
    @Binding var currentURL: String
    @Binding var isLoading: Bool
    @Binding var webViewRef: WKWebView?
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool

    private static let videoExtensions = ["mp4", "mov", "m4v", "webm", "mkv"]
    private static let downloadExtensions = ["zip", "mlw"]

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsAirPlayForMediaPlayback = false
        // Refuse JavaScript-driven `window.open()` without a user gesture —
        // common popup spam / drive-by-download vector when the user
        // browses untrusted sites in Discover.
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // Observe canGoBack / canGoForward via KVO
        context.coordinator.observeNavigation(of: webView)

        DispatchQueue.main.async { self.webViewRef = webView }

        // HTTPS/HTTP only. Reject `file://`, `javascript:`, custom schemes
        // — prevents local-file disclosure and JS execution against the
        // WebView origin via crafted address bar input.
        if let url = URL(string: urlString),
           let scheme = url.scheme?.lowercased(),
           scheme == "https" || scheme == "http" {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        let parent: WebViewWrapper
        private var backObservation: NSKeyValueObservation?
        private var forwardObservation: NSKeyValueObservation?
        /// Tracks pending WKDownload info: destination, display name, and DownloadManager tracking ID
        private var pendingDownloads: [WKDownload: (dest: URL, name: String, trackingID: UUID)] = [:]
        private var progressObservations: [WKDownload: NSKeyValueObservation] = [:]

        init(_ parent: WebViewWrapper) { self.parent = parent }

        func observeNavigation(of webView: WKWebView) {
            backObservation = webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async { self?.parent.canGoBack = wv.canGoBack }
            }
            forwardObservation = webView.observe(\.canGoForward, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async { self?.parent.canGoForward = wv.canGoForward }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            parent.currentURL = webView.url?.absoluteString ?? ""
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            parent.currentURL = webView.url?.absoluteString ?? ""
        }

        // MARK: - WKUIDelegate (handle window.open popups)

        /// Intercept window.open() — load in current WebView instead of opening a new window.
        /// Sites like moewalls.com use window.open() for downloads.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                Log.browser.info("Popup intercepted: \(url.absoluteString, privacy: .public)")
                webView.load(navigationAction.request)
            }
            return nil
        }

        /// Intercept navigation - catch video file downloads by extension
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let ext = url.pathExtension.lowercased()

            // If user clicked a video file link, intercept and download
            if WebViewWrapper.videoExtensions.contains(ext) {
                decisionHandler(.cancel)
                let name = url.deletingPathExtension().lastPathComponent
                Log.browser.info("Intercepted video: \(url.absoluteString, privacy: .public)")
                DownloadManager.shared.downloadAndImport(name: name, from: url)
                return
            }

            decisionHandler(.allow)
        }

        /// Intercept response - use WKDownload for video, archives, and octet-stream with video filenames
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            let mimeType = navigationResponse.response.mimeType ?? ""
            let url = navigationResponse.response.url

            // Intercept video responses → WKDownload
            if mimeType.starts(with: "video/") {
                Log.browser.info("Starting WKDownload for video: \(url?.absoluteString ?? "?", privacy: .public) (\(mimeType, privacy: .public))")
                decisionHandler(.download)
                return
            }

            // Archives (zip/mlw) → WKDownload
            let archiveMimes = ["application/zip", "application/x-zip-compressed"]
            if archiveMimes.contains(mimeType) {
                Log.browser.info("Starting WKDownload for archive: \(url?.absoluteString ?? "?", privacy: .public) (\(mimeType, privacy: .public))")
                decisionHandler(.download)
                return
            }

            // application/octet-stream — check Content-Disposition for video filename
            // Sites like moewalls.com serve video as octet-stream with filename=...mp4
            if mimeType == "application/octet-stream" {
                let disposition = (navigationResponse.response as? HTTPURLResponse)?
                    .value(forHTTPHeaderField: "Content-Disposition") ?? ""
                let videoExts = ["mp4", "mov", "m4v", "webm", "mkv", "zip", "mlw"]
                let hasVideoFilename = videoExts.contains { disposition.lowercased().contains(".\($0)") }

                if hasVideoFilename {
                    Log.browser.info("Starting WKDownload for octet-stream: \(url?.absoluteString ?? "?", privacy: .public) (disposition: \(disposition, privacy: .public))")
                    decisionHandler(.download)
                    return
                }
            }

            decisionHandler(.allow)
        }

        // MARK: - WKDownload bridging

        /// Called when a navigation response becomes a WKDownload
        func webView(_ webView: WKWebView,
                     navigationResponse: WKNavigationResponse,
                     didBecome download: WKDownload) {
            download.delegate = self
        }

        /// Called when a navigation action becomes a WKDownload
        func webView(_ webView: WKWebView,
                     navigationAction: WKNavigationAction,
                     didBecome download: WKDownload) {
            download.delegate = self
        }

        // MARK: - WKDownloadDelegate

        func download(_ download: WKDownload,
                      decideDestinationUsing response: URLResponse,
                      suggestedFilename: String,
                      completionHandler: @escaping (URL?) -> Void) {
            let name = (suggestedFilename as NSString).deletingPathExtension
            let ext = (suggestedFilename as NSString).pathExtension.lowercased()
            let destExt = ext.isEmpty ? "zip" : ext
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(destExt)

            // Register in DownloadManager for UI progress tracking
            let trackingID = DownloadManager.shared.trackDownload(name: name)
            pendingDownloads[download] = (dest: dest, name: name, trackingID: trackingID)

            // Observe download progress via KVO
            let obs = download.progress.observe(\.fractionCompleted, options: [.new]) { progress, _ in
                DispatchQueue.main.async {
                    DownloadManager.shared.updateProgress(id: trackingID, progress: progress.fractionCompleted)
                }
            }
            progressObservations[download] = obs

            Log.browser.info("WKDownload saving to: \(dest.lastPathComponent, privacy: .public) (name: \(name, privacy: .public))")
            completionHandler(dest)
        }

        func downloadDidFinish(_ download: WKDownload) {
            guard let info = pendingDownloads.removeValue(forKey: download) else { return }
            progressObservations.removeValue(forKey: download)

            // Update UI: show "Processing..." state at 100%
            DownloadManager.shared.updateProgress(id: info.trackingID, progress: 1.0)
            Log.browser.info("WKDownload complete: \(info.name, privacy: .public)")

            // Process: ZIP → MLW → MP4 → import
            let trackingID = info.trackingID
            Task {
                do {
                    let importURL = try processDownloadedFile(at: info.dest, name: info.name)
                    _ = try await WallpaperManager.shared.importVideo(from: importURL)
                    try? FileManager.default.removeItem(at: importURL)
                    if importURL != info.dest {
                        try? FileManager.default.removeItem(at: info.dest)
                    }
                    Log.browser.info("Imported: \(info.name, privacy: .public)")
                    await MainActor.run {
                        DownloadManager.shared.completeDownload(id: trackingID)
                    }
                } catch {
                    Log.browser.error("Import failed for \(info.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    await MainActor.run {
                        DownloadManager.shared.failDownload(id: trackingID)
                        ErrorReporter.shared.report(error, context: "Could not import \(info.name)")
                    }
                }
            }
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            let info = pendingDownloads.removeValue(forKey: download)
            progressObservations.removeValue(forKey: download)
            if let info {
                DownloadManager.shared.failDownload(id: info.trackingID)
            }
            Log.browser.error("WKDownload failed: \(info?.name ?? "?", privacy: .public) – \(error.localizedDescription, privacy: .public)")
        }

        /// Process a downloaded file — detect format and decrypt if needed
        private func processDownloadedFile(at localURL: URL, name: String) throws -> URL {
            // Check file magic bytes to determine type
            let handle = try FileHandle(forReadingFrom: localURL)
            defer { try? handle.close() }
            let header = handle.readData(ofLength: 16)

            // ZIP file → extract .mlw → decrypt
            if header.count >= 4 && header[0] == 0x50 && header[1] == 0x4b
                && header[2] == 0x03 && header[3] == 0x04 {
                Log.browser.info("Processing ZIP for MLW: \(name, privacy: .public)")
                let mp4URL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mp4")
                try MLWDecryptor.decryptFromZIP(fileAt: localURL, to: mp4URL)
                return mp4URL
            }

            // MLW file → decrypt directly
            if header.count >= 9 && (header.starts(with: Data("MLW.VIDEO".utf8))
                || header.starts(with: Data("MLW.DEPTH".utf8))) {
                Log.browser.info("Processing MLW: \(name, privacy: .public)")
                let mp4URL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mp4")
                try MLWDecryptor.decrypt(fileAt: localURL, to: mp4URL)
                return mp4URL
            }

            // Already a video file
            return localURL
        }
    }
}
