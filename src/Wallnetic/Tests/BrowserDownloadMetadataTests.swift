import WebKit
import XCTest
@testable import Wallnetic

@MainActor
final class BrowserDownloadMetadataTests: XCTestCase {
    func testVideoThenPageTitlePrecedesFilenameWithoutStrippingTitlePunctuation() {
        XCTAssertEqual(BrowserDownloadMetadata.name(title: "Ocean.v2", pageTitle: "Gallery",
                                                     filename: "8C343.mp4"), "Ocean.v2")
        XCTAssertEqual(BrowserDownloadMetadata.name(pageTitle: "Night & Stars",
                                                     filename: "8C343.mp4"), "Night & Stars")
    }

    func testInvalidTitlesFallBackToPageThenFilename() {
        XCTAssertEqual(BrowserDownloadMetadata.name(title: " \n\t", pageTitle: "Sunset",
                                                     filename: "8C343.mp4"), "Sunset")
        XCTAssertEqual(BrowserDownloadMetadata.name(title: String(repeating: "x", count: 4097),
            pageTitle: "\u{0000}\u{202E}", filename: "../../Ocean.MP4"), "Ocean")
        XCTAssertEqual(BrowserDownloadMetadata.name(filename: nil), "Wallpaper")
    }

    func testTitlesAreBoundedPlainTextAndSourceURLsRemainUnchanged() throws {
        let url = "https://example.invalid/2e15870.mp4?token=sample"
        let title = " ../../Ocean\n Gökyüzü 👩‍🚀\u{0000}\u{202E} "
        let video = try XCTUnwrap(BrowserDownloadMetadata.videos(from: [["url": url, "title": title]]).first)
        XCTAssertEqual(video.name, "../../Ocean Gökyüzü 👩‍🚀")
        XCTAssertEqual(video.url.absoluteString, url)
        XCTAssertEqual(BrowserDownloadMetadata.name(title: String(repeating: "🌅", count: 200),
            filename: "a.mp4"), String(repeating: "🌅", count: 160))
    }

    func testScanParsingRejectsNonNetworkURLsAndDeduplicatesByURLNotTitle() {
        let rows: [[String: Any]] = [
            ["url": "file:///tmp/a.mp4", "title": "Local"],
            ["url": "javascript:alert(1)", "title": "Script"],
            ["url": "data:video/mp4;base64,AA", "title": "Data"],
            ["url": 42, "title": "Invalid"],
            ["url": "https://example.invalid/a.mp4", "title": "Same title"],
            ["url": "https://example.invalid/a.mp4", "title": "Duplicate"],
            ["url": "https://example.invalid/b.mp4", "title": "Same title"]
        ]
        let videos = BrowserDownloadMetadata.videos(from: rows)
        XCTAssertEqual(videos.map(\.name), ["Same title", "Same title"])
        XCTAssertNotEqual(videos.first?.id, videos.last?.id)
        XCTAssertTrue(BrowserDownloadMetadata.videos(from: "invalid result").isEmpty)
    }

    func testDOMScanReadsVideoLabelsPageTitleAndRelativeMediaURLs() async throws {
        let webView = try await page("""
        <title>Night &amp; Stars</title>
        <video title="Ocean Twilight" preload="none"><source src="/ocean.mp4"></video>
        <a href="/forest.webm" aria-label="Yeşil Orman">Download</a>
        <a href="/random-id.mov">Download</a>
        <a href="/random-id.mov">Duplicate</a>
        <meta property="og:video" content="https://cdn.example.invalid/media?id=42">
        <a href="file:///tmp/local.mp4">Local</a>
        <a href="javascript:alert('video.mp4')">Script</a>
        """)
        let videos = BrowserDownloadMetadata.videos(from: try await webView.evaluateJavaScript(BrowserDownloadMetadata.scanScript))
        XCTAssertEqual(videos.map(\.name), ["Ocean Twilight", "Yeşil Orman", "Night & Stars", "Night & Stars"])
        XCTAssertEqual(videos.map(\.url.absoluteString), ["https://example.invalid/ocean.mp4",
            "https://example.invalid/forest.webm", "https://example.invalid/random-id.mov",
            "https://cdn.example.invalid/media?id=42"])
        // macOS 26's WebKit can update `title` after didFinish. The app reads it
        // when a link is clicked, long after the page loaded, so wait for it here.
        let titled = XCTKVOExpectation(keyPath: "title", object: webView,
                                       expectedValue: "Night & Stars", options: [.initial, .new])
        await fulfillment(of: [titled], timeout: 5)
        XCTAssertEqual(BrowserDownloadMetadata.name(pageTitle: webView.title, filename: "random.zip"), "Night & Stars")
    }

    func testScannedTitlesRemainAssociatedWithTheirPageAfterTitleChanges() async throws {
        let webView = try await page("<title>First page</title><a href='/a.mp4'>Download</a>")
        let first = BrowserDownloadMetadata.videos(from: try await webView.evaluateJavaScript(BrowserDownloadMetadata.scanScript))
        _ = try await webView.evaluateJavaScript("document.title = 'Second page'")
        let second = BrowserDownloadMetadata.videos(from: try await webView.evaluateJavaScript(BrowserDownloadMetadata.scanScript))
        XCTAssertEqual(first.first?.name, "First page")
        XCTAssertEqual(second.first?.name, "Second page")
        XCTAssertEqual(first.first?.id, second.first?.id)
    }

    func testDOMTitleContainingCodeIsReturnedAsTextAndNeverExecuted() async throws {
        let title = "');window.wallneticInjected=true;//"
        let webView = try await page("<title>\(title)</title><a href='/a.mp4'>Download</a>")
        let videos = BrowserDownloadMetadata.videos(from: try await webView.evaluateJavaScript(BrowserDownloadMetadata.scanScript))
        XCTAssertEqual(videos.first?.name, title)
        let marker = try await webView.evaluateJavaScript("typeof window.wallneticInjected") as? String
        XCTAssertEqual(marker, "undefined")
    }

    private func page(_ html: String) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let loaded = expectation(description: "Local HTML fixture loaded")
        let observer = FixtureNavigationObserver(loaded: loaded)
        webView.navigationDelegate = observer
        // Fixtures never fetch media or execute embedded scripts.
        let policy = "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'\">"
        webView.loadHTMLString(policy + html, baseURL: URL(string: "https://example.invalid/"))
        await fulfillment(of: [loaded], timeout: 15)
        if let error = observer.error { throw error }
        webView.navigationDelegate = nil
        return webView
    }
}

/// Not marked @MainActor: the macOS 14 SDK's WKNavigationDelegate methods are
/// nonisolated, and newer SDKs isolate the protocol, and so this class, to
/// the main actor. WebKit calls it on the main thread either way.
private final class FixtureNavigationObserver: NSObject, WKNavigationDelegate {
    let loaded: XCTestExpectation
    var error: Error?

    init(loaded: XCTestExpectation) { self.loaded = loaded }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded.fulfill() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.error = error
        loaded.fulfill()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.error = error
        loaded.fulfill()
    }
}
