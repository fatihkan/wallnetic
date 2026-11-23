import XCTest
@testable import Wallnetic

final class WallpaperPreviewLayoutTests: XCTestCase {
    private let bounds = CGSize(width: 720, height: 420)

    func testStageKeepsTheDisplayShapeAndFitsItsBounds() {
        let displays: [CGSize] = [
            CGSize(width: 1920, height: 1080),   // 16:9
            CGSize(width: 2560, height: 1600),   // 16:10
            CGSize(width: 3440, height: 1440),   // ultrawide
            CGSize(width: 1080, height: 1920),   // a rotated display
        ]
        for display in displays {
            let stage = WallpaperPreviewLayout.stageSize(displaySize: display, fitting: bounds)
            XCTAssertLessThanOrEqual(stage.width, bounds.width)
            XCTAssertLessThanOrEqual(stage.height, bounds.height)
            XCTAssertEqual(stage.width / stage.height, display.width / display.height, accuracy: 0.01)
            XCTAssertTrue(stage.width == bounds.width || stage.height == bounds.height,
                          "The stage uses all the room on one side")
        }
    }

    func testAnUnknownDisplaySizeFallsBackToTheBounds() {
        XCTAssertEqual(WallpaperPreviewLayout.stageSize(displaySize: .zero, fitting: bounds), bounds)
    }

    func testVisibleFractionLeavesOutTheMenuBarAndTheDock() {
        // A 1920x1080 display at the origin: a 25 pt menu bar on top, a 70 pt Dock below.
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let visible = CGRect(x: 0, y: 70, width: 1920, height: 985)
        let fraction = WallpaperPreviewLayout.visibleFraction(screenFrame: screen, visibleFrame: visible)
        XCTAssertEqual(fraction.minY, 70.0 / 1080, accuracy: 0.0001)
        XCTAssertEqual(fraction.height, 985.0 / 1080, accuracy: 0.0001)
        XCTAssertEqual(fraction.width, 1, accuracy: 0.0001)

        // A second display left of the main one keeps the same fractions.
        let other = WallpaperPreviewLayout.visibleFraction(
            screenFrame: screen.offsetBy(dx: -1920, dy: 300), visibleFrame: visible.offsetBy(dx: -1920, dy: 300))
        XCTAssertEqual(other.minX, fraction.minX, accuracy: 0.0001)
        XCTAssertEqual(other.minY, fraction.minY, accuracy: 0.0001)
    }

    func testTheVisibleAreaScalesWithTheStage() {
        let fraction = CGRect(x: 0, y: 0.1, width: 1, height: 0.85)
        let rect = WallpaperPreviewLayout.rect(fraction, in: CGSize(width: 720, height: 400))
        XCTAssertEqual(rect, CGRect(x: 0, y: 40, width: 720, height: 340))
    }
}
