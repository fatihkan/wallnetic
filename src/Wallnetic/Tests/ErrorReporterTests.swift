import XCTest
@testable import Wallnetic

@MainActor
final class ErrorReporterTests: XCTestCase {
    override func setUp() async throws {
        ErrorReporter.shared.dismissCurrent()
    }

    override func tearDown() async throws {
        ErrorReporter.shared.dismissCurrent()
    }

    func testReportPublishesAppError() async throws {
        let dummy = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "boom"])
        ErrorReporter.shared.report(dummy, context: "Test context")

        // The reporter dispatches to the main actor via Task — wait one cycle.
        try await Task.sleep(nanoseconds: 50_000_000)

        let current = ErrorReporter.shared.current
        XCTAssertNotNil(current)
        XCTAssertEqual(current?.title, "Test context")
        XCTAssertEqual(current?.message, "boom")
    }

    func testReportSurfaceFalseDoesNotPublish() async throws {
        let dummy = NSError(domain: "test", code: 1, userInfo: nil)
        ErrorReporter.shared.report(dummy, context: "Silent path", surface: false)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(ErrorReporter.shared.current)
    }
}
