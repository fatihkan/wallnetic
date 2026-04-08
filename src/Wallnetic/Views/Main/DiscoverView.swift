import SwiftUI
import WebKit

// MARK: - Source Model

struct WallpaperSource: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let color: Color
    let url: String
    let type: SourceType
    let estimatedCount: String

    enum SourceType {
        case api      // Pixabay, Pexels
        case browser  // MyLiveWallpapers, DesktopHut, etc.
    }

    static let allSources: [WallpaperSource] = [
        WallpaperSource(id: "pixabay", name: "Pixabay", description: "Free stock videos and animations",
                        icon: "photo.artframe", color: .green, url: "https://pixabay.com/videos/",
                        type: .api, estimatedCount: "6,000+"),
        WallpaperSource(id: "pexels", name: "Pexels", description: "Free HD & 4K stock videos",
                        icon: "play.rectangle.fill", color: .teal, url: "https://www.pexels.com/videos/",
                        type: .api, estimatedCount: "52,000+"),
        WallpaperSource(id: "mylivewallpapers", name: "MyLiveWallpapers", description: "Curated live wallpaper collection",
                        icon: "sparkles.rectangle.stack", color: .purple, url: "https://mylivewallpapers.com",
                        type: .browser, estimatedCount: "5,000+"),
        WallpaperSource(id: "desktophut", name: "DesktopHut", description: "4K anime, nature, space wallpapers",
                        icon: "desktopcomputer", color: .blue, url: "https://www.desktophut.com",
                        type: .browser, estimatedCount: "3,000+"),
        WallpaperSource(id: "moewalls", name: "MoeWalls", description: "Anime and general live wallpapers",
                        icon: "sparkles.tv", color: .pink, url: "https://moewalls.com",
                        type: .browser, estimatedCount: "4,000+"),
        WallpaperSource(id: "motionbgs", name: "MotionBGs", description: "4K animated backgrounds",
                        icon: "film.stack", color: .orange, url: "https://motionbgs.com",
                        type: .browser, estimatedCount: "8,790+"),
    ]
}

// MARK: - Discover View

struct DiscoverView: View {
    @State private var selectedSource: WallpaperSource?
    @State private var showingBrowser = false

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header with glow
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                        .neonGlow(.blue, isActive: true, radius: 6)
                    Text("Discover Wallpapers")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                Spacer()

                Text("\(WallpaperSource.allSources.count)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor)
                +
                Text(" sources")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            // Source grid with staggered entrance
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(WallpaperSource.allSources.enumerated()), id: \.element.id) { index, source in
                        SourceCard(source: source)
                            .staggered(index: index)
                            .onTapGesture {
                                selectedSource = source
                                showingBrowser = true
                            }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
        }
        .background(Color.clear)
        .overlay {
            if showingBrowser, let source = selectedSource {
                InAppBrowserView(source: source, isPresented: $showingBrowser)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: Anim.medium, dampingFraction: 0.85), value: showingBrowser)
    }
}

// MARK: - Source Card

struct SourceCard: View {
    let source: WallpaperSource
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 16) {
            // Icon with glow
            Image(systemName: source.icon)
                .font(.system(size: 24))
                .foregroundColor(source.color)
                .neonGlow(source.color, isActive: isHovering, radius: 8)
                .frame(width: 50, height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(source.color.opacity(isHovering ? 0.15 : 0.08))
                )

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(source.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)

                    if source.type == .api {
                        Text("API")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                            .neonGlow(.green, isActive: isHovering, radius: 3)
                    }
                }

                Text(source.description)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(2)

                Text("\(source.estimatedCount) wallpapers")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(source.color.opacity(0.7))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isHovering ? source.color.opacity(0.6) : .white.opacity(0.2))
                .offset(x: isHovering ? 3 : 0)
        }
        .padding(16)
        .frame(height: 90)
        .glowCard(isHovering: isHovering, cornerRadius: 12, glowColor: source.color)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isHovering ? 0.06 : 0.03))
        )
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.spring(response: Anim.enter, dampingFraction: 0.75), value: isHovering)
        .onHover { h in isHovering = h }
    }
}

// MARK: - In-App Browser

struct InAppBrowserView: View {
    let source: WallpaperSource
    @Binding var isPresented: Bool
    @ObservedObject var downloadManager = DownloadManager.shared
    @State private var currentURL: String
    @State private var isLoading = true
    @State private var foundVideos: [String] = []
    @State private var showingVideos = false
    @State private var webView: WKWebView?
    @State private var canGoBack = false
    @State private var canGoForward = false

    init(source: WallpaperSource, isPresented: Binding<Bool>) {
        self.source = source
        self._isPresented = isPresented
        self._currentURL = State(initialValue: source.url)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Browser toolbar
            HStack(spacing: 12) {
                // Source info
                Image(systemName: source.icon)
                    .foregroundColor(source.color)
                Text(source.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                // Back / Forward
                HStack(spacing: 2) {
                    Button {
                        webView?.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(canGoBack ? .white.opacity(0.8) : .white.opacity(0.2))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(canGoBack ? 0.1 : 0.04))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGoBack)

                    Button {
                        webView?.goForward()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(canGoForward ? .white.opacity(0.8) : .white.opacity(0.2))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(canGoForward ? 0.1 : 0.04))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGoForward)
                }

                // URL bar
                Text(currentURL)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(6)

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                }

                // Scan page for videos
                Button {
                    scanPageForVideos()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 11))
                        Text("Scan")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                // Download indicator
                if downloadManager.activeCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                        Text("\(downloadManager.activeCount)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(6)
                }

                // Close
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(white: 0.12))

            // Active downloads bar
            if !downloadManager.downloads.filter({ [.downloading, .completed, .failed].contains($0.status) }).isEmpty {
                VStack(spacing: 4) {
                    ForEach(downloadManager.downloads.filter({ [.downloading, .completed, .failed].contains($0.status) })) { dl in
                        HStack(spacing: 8) {
                            if dl.status == .downloading {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 9))
                                    .foregroundColor(.green)
                            } else if dl.status == .completed {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.red)
                            }

                            Text(dl.name)
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)

                            if dl.status == .downloading {
                                ProgressView(value: dl.progress)
                                    .frame(width: 100)

                                Text("\(Int(dl.progress * 100))%")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                                    .frame(width: 30)
                            } else if dl.status == .completed {
                                Text("Imported")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.green)
                            } else {
                                Text("Failed")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color(white: 0.08))
            }

            // Found videos panel
            if !foundVideos.isEmpty {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "film.stack")
                            .foregroundColor(.blue)
                        Text("Found \(foundVideos.count) video\(foundVideos.count == 1 ? "" : "s") on this page")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)

                        Spacer()

                        Button("Download All") {
                            for url in foundVideos {
                                if let videoURL = URL(string: url) {
                                    let name = videoURL.deletingPathExtension().lastPathComponent
                                    DownloadManager.shared.downloadAndImport(name: name, from: videoURL)
                                }
                            }
                            foundVideos = []
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.green)
                        .buttonStyle(.plain)

                        Button {
                            foundVideos = []
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    // Video list
                    ForEach(foundVideos, id: \.self) { urlStr in
                        HStack(spacing: 8) {
                            Image(systemName: "film")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.4))

                            Text(URL(string: urlStr)?.lastPathComponent ?? urlStr)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                                .lineLimit(1)

                            Spacer()

                            Button("Download") {
                                if let videoURL = URL(string: urlStr) {
                                    let name = videoURL.deletingPathExtension().lastPathComponent
                                    DownloadManager.shared.downloadAndImport(name: name, from: videoURL)
                                    foundVideos.removeAll { $0 == urlStr }
                                }
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.blue)
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 3)
                    }
                }
                .background(Color(white: 0.06))
            }

            // WebView
            WebViewWrapper(
                urlString: source.url,
                currentURL: $currentURL,
                isLoading: $isLoading,
                webViewRef: $webView,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward
            )
        }
        .background(Color.black)
    }

    /// Scans current page for video URLs using JavaScript
    private func scanPageForVideos() {
        let js = """
        (function() {
            var videos = [];
            // Find <video> source elements
            document.querySelectorAll('video source, video').forEach(function(el) {
                var src = el.src || el.currentSrc;
                if (src && src.match(/\\.(mp4|mov|m4v|webm)/i)) videos.push(src);
            });
            // Find direct <a> links to video files
            document.querySelectorAll('a[href]').forEach(function(el) {
                var href = el.href;
                if (href && href.match(/\\.(mp4|mov|m4v|webm)/i)) videos.push(href);
            });
            // Find og:video meta tags
            document.querySelectorAll('meta[property="og:video"]').forEach(function(el) {
                if (el.content) videos.push(el.content);
            });
            return [...new Set(videos)];
        })();
        """

        webView?.evaluateJavaScript(js) { result, error in
            if let urls = result as? [String] {
                DispatchQueue.main.async {
                    self.foundVideos = urls
                    if urls.isEmpty {
                        NSLog("[Browser] No videos found on page")
                    } else {
                        NSLog("[Browser] Found %d videos", urls.count)
                    }
                }
            }
        }
    }
}

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
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // Observe canGoBack / canGoForward via KVO
        context.coordinator.observeNavigation(of: webView)

        DispatchQueue.main.async { self.webViewRef = webView }

        if let url = URL(string: urlString) {
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
                NSLog("[Browser] Popup intercepted: %@", url.absoluteString)
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
                NSLog("[Browser] Intercepted video: %@", url.absoluteString)
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
                NSLog("[Browser] Starting WKDownload for video: %@ (%@)", url?.absoluteString ?? "?", mimeType)
                decisionHandler(.download)
                return
            }

            // Archives (zip/mlw) → WKDownload
            let archiveMimes = ["application/zip", "application/x-zip-compressed"]
            if archiveMimes.contains(mimeType) {
                NSLog("[Browser] Starting WKDownload for archive: %@ (%@)", url?.absoluteString ?? "?", mimeType)
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
                    NSLog("[Browser] Starting WKDownload for octet-stream: %@ (disposition: %@)",
                          url?.absoluteString ?? "?", disposition)
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

            NSLog("[Browser] WKDownload saving to: %@ (name: %@)", dest.lastPathComponent, name)
            completionHandler(dest)
        }

        func downloadDidFinish(_ download: WKDownload) {
            guard let info = pendingDownloads.removeValue(forKey: download) else { return }
            progressObservations.removeValue(forKey: download)

            // Update UI: show "Processing..." state at 100%
            DownloadManager.shared.updateProgress(id: info.trackingID, progress: 1.0)
            NSLog("[Browser] WKDownload complete: %@", info.name)

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
                    NSLog("[Browser] Imported: %@", info.name)
                    await MainActor.run {
                        DownloadManager.shared.completeDownload(id: trackingID)
                    }
                } catch {
                    NSLog("[Browser] Import failed for %@: %@", info.name, error.localizedDescription)
                    await MainActor.run {
                        DownloadManager.shared.failDownload(id: trackingID)
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
            NSLog("[Browser] WKDownload failed: %@ – %@", info?.name ?? "?", error.localizedDescription)
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
                NSLog("[Browser] Processing ZIP for MLW: %@", name)
                let mp4URL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mp4")
                try MLWDecryptor.decryptFromZIP(fileAt: localURL, to: mp4URL)
                return mp4URL
            }

            // MLW file → decrypt directly
            if header.count >= 9 && (header.starts(with: Data("MLW.VIDEO".utf8))
                || header.starts(with: Data("MLW.DEPTH".utf8))) {
                NSLog("[Browser] Processing MLW: %@", name)
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
