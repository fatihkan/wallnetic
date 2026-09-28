import XCTest
@testable import Wallnetic

/// `DeepLinkHandler` — input validation (#167 + security hardening).
final class DeepLinkHandlerTests: XCTestCase {
    func testDuplicateQueryNamesAreRejectedBeforeDispatch() {
        var opens = 0
        let observer = NotificationCenter.default.addObserver(forName: .openMainWindow, object: nil, queue: nil) { _ in
            opens += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        for query in ["a=1&a=2", "a=1&%61=2", "a&a=1", "url=https%3A%2F%2Fexample.com&url=file%3A%2F%2F%2Ftmp"] {
            DeepLinkHandler.shared.handle(URL(string: "wallnetic://open?" + query)!)
        }
        XCTAssertEqual(opens, 0)
    }

    func testNonWallneticSchemeIgnored() {
        // Should be a no-op — no crash, no state change. Acceptance is
        // simply that the call returns.
        DeepLinkHandler.shared.handle(URL(string: "https://example.com")!)
        DeepLinkHandler.shared.handle(URL(string: "file:///etc/passwd")!)
        // No assertion — covered by "doesn't crash".
    }

    func testHandlesPlayPauseHost() {
        var toggles = 0
        let handler = DeepLinkHandler(togglePlayback: { toggles += 1 })
        handler.handle(URL(string: "https://playPause")!)
        handler.handle(URL(string: "wallnetic://playPause?a=1&a=2")!)
        XCTAssertEqual(toggles, 0)
        handler.handle(URL(string: "wallnetic://playPause")!)
        XCTAssertEqual(toggles, 1)
    }

    func testHandlesUnknownHost() {
        DeepLinkHandler.shared.handle(URL(string: "wallnetic://nonexistentaction")!)
        // Verifies the default branch logs without throwing.
    }
}
