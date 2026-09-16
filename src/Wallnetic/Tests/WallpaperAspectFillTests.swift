import XCTest
@testable import Wallnetic

final class WallpaperAspectFillTests: XCTestCase {

    func testWiderVideoCropsLeftAndRight() {
        // 16:9 video on a 4:3 view — crop the sides, keep full height.
        let rect = WallpaperAspectFill.textureRect(
            videoSize: CGSize(width: 1920, height: 1080),
            viewSize: CGSize(width: 1440, height: 1080)
        )
        XCTAssertEqual(rect.minY, 0, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 1, accuracy: 0.0001)
        XCTAssertGreaterThan(rect.minX, 0)
        XCTAssertLessThan(rect.maxX, 1)
        XCTAssertEqual(rect.width, (1440.0 / 1080.0) / (1920.0 / 1080.0), accuracy: 0.0001)
    }

    func testTallerVideoCropsTopAndBottom() {
        // 9:16 video on a 16:9 view — crop top/bottom, keep full width.
        let rect = WallpaperAspectFill.textureRect(
            videoSize: CGSize(width: 1080, height: 1920),
            viewSize: CGSize(width: 1920, height: 1080)
        )
        XCTAssertEqual(rect.minX, 0, accuracy: 0.0001)
        XCTAssertEqual(rect.width, 1, accuracy: 0.0001)
        XCTAssertGreaterThan(rect.minY, 0)
        XCTAssertLessThan(rect.maxY, 1)
    }

    func testMatchingAspectUsesFullTexture() {
        let rect = WallpaperAspectFill.textureRect(
            videoSize: CGSize(width: 1920, height: 1080),
            viewSize: CGSize(width: 1920, height: 1080)
        )
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testKeyframeRewindIsDiscarded() {
        // 3 frames back at 30 fps ≈ 0.1s — hold the last frame.
        XCTAssertTrue(WallpaperAspectFill.shouldDiscardRewoundFrame(
            previousSeconds: 12.5, newSeconds: 12.4
        ))
    }

    func testLoopResetIsKept() {
        XCTAssertFalse(WallpaperAspectFill.shouldDiscardRewoundFrame(
            previousSeconds: 30.0, newSeconds: 0.0
        ))
    }

    func testForwardTimeIsKept() {
        XCTAssertFalse(WallpaperAspectFill.shouldDiscardRewoundFrame(
            previousSeconds: 12.4, newSeconds: 12.5
        ))
    }
}
