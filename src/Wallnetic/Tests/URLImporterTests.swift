import XCTest
@testable import Wallnetic

/// Validates the `URLImporter` security boundary added in #167 / security
/// hardening pass. These tests exercise the synchronous validation paths
/// only — actual network downloads are not exercised here.
@MainActor
final class URLImporterTests: XCTestCase {
    func testInvalidURLStringThrows() async {
        do {
            _ = try await URLImporter.shared.downloadAndImport(from: "not a url ::: at all")
            XCTFail("Expected invalidURL")
        } catch URLImportError.invalidURL {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNonHTTPSchemeRejected() async {
        do {
            _ = try await URLImporter.shared.downloadAndImport(from: "file:///etc/passwd")
            XCTFail("Expected invalidScheme")
        } catch URLImportError.invalidScheme {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHTTPRejected() async {
        do {
            _ = try await URLImporter.shared.downloadAndImport(from: "http://example.com/video.mp4")
            XCTFail("Expected invalidScheme")
        } catch URLImportError.invalidScheme {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testIsVideoURLAcceptsKnownExtensions() {
        XCTAssertTrue(URLImporter.shared.isVideoURL("https://example.com/clip.mp4"))
        XCTAssertTrue(URLImporter.shared.isVideoURL("https://example.com/clip.MOV"))
        XCTAssertTrue(URLImporter.shared.isVideoURL("https://example.com/clip.gif"))
    }

    func testIsVideoURLRejectsUnknownExtensions() {
        XCTAssertFalse(URLImporter.shared.isVideoURL("https://example.com/clip.exe"))
        XCTAssertFalse(URLImporter.shared.isVideoURL("https://example.com/clip"))
        XCTAssertFalse(URLImporter.shared.isVideoURL(""))
    }
}
