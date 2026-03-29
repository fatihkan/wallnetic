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
            // Header
            HStack {
                Image(systemName: "globe")
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
                Text("Discover Wallpapers")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Spacer()

                Text("\(WallpaperSource.allSources.count) sources")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            // Source grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(WallpaperSource.allSources) { source in
                        SourceCard(source: source)
                            .onTapGesture {
                                selectedSource = source
                                showingBrowser = true
                            }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .background(Color.black)
        .overlay {
            if showingBrowser, let source = selectedSource {
                InAppBrowserView(source: source, isPresented: $showingBrowser)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showingBrowser)
    }
}

// MARK: - Source Card

struct SourceCard: View {
    let source: WallpaperSource
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: source.icon)
                .font(.system(size: 24))
                .foregroundColor(source.color)
                .frame(width: 50, height: 50)
                .background(source.color.opacity(0.15))
                .cornerRadius(12)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(source.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)

                    if source.type == .api {
                        Text("API")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(3)
                    }
                }

                Text(source.description)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(2)

                Text("\(source.estimatedCount) wallpapers")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(source.color.opacity(0.8))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(16)
        .frame(height: 90)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isHovering ? 0.08 : 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(isHovering ? 0.15 : 0.06), lineWidth: 1)
                )
        )
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovering)
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
            if !downloadManager.downloads.filter({ $0.status == .downloading }).isEmpty {
                VStack(spacing: 4) {
                    ForEach(downloadManager.downloads.filter({ $0.status == .downloading })) { dl in
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 9))
                                .foregroundColor(.green)

                            Text(dl.name)
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)

                            ProgressView(value: dl.progress)
                                .frame(width: 100)

                            Text("\(Int(dl.progress * 100))%")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .frame(width: 30)
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
                webViewRef: $webView
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

    private static let videoExtensions = ["mp4", "mov", "m4v", "webm", "mkv"]

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsAirPlayForMediaPlayback = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        DispatchQueue.main.async { self.webViewRef = webView }

        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebViewWrapper

        init(_ parent: WebViewWrapper) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            parent.currentURL = webView.url?.absoluteString ?? ""
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            parent.currentURL = webView.url?.absoluteString ?? ""
        }

        /// Intercept navigation - catch video file downloads
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

        /// Intercept response - catch video content-type downloads
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let mimeType = navigationResponse.response.mimeType,
               mimeType.starts(with: "video/") {
                // This is a video response - download it
                if let url = navigationResponse.response.url {
                    let name = url.deletingPathExtension().lastPathComponent
                    NSLog("[Browser] Intercepted video response: %@", url.absoluteString)
                    decisionHandler(.cancel)
                    DownloadManager.shared.downloadAndImport(name: name, from: url)
                    return
                }
            }

            decisionHandler(.allow)
        }
    }
}
