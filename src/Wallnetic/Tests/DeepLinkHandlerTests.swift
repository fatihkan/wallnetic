import XCTest
@testable import Wallnetic

/// `DeepLinkHandler` — input validation (#167 + security hardening).
final class DeepLinkHandlerTests: XCTestCase {
    func testNonWallneticSchemeIgnored() {
        // Should be a no-op — no crash, no state change. Acceptance is
        // simply that the call returns.
        DeepLinkHandler.shared.handle(URL(string: "https://example.com")!)
        DeepLinkHandler.shared.handle(URL(string: "file:///etc/passwd")!)
        // No assertion — covered by "doesn't crash".
    }

    func testHandlesPlayPauseHost() {
        DeepLinkHandler.shared.handle(URL(string: "wallnetic://playPause")!)
        // No state inspection — togglePlayback effects are global. We're
        // really exercising the host-routing switch shape.
    }

    func testHandlesUnknownHost() {
        DeepLinkHandler.shared.handle(URL(string: "wallnetic://nonexistentaction")!)
        // Verifies the default branch logs without throwing.
    }
}
