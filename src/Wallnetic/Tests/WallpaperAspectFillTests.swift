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

    // MARK: - Crop of the drawn frame (#307)

    private let landscape = CGSize(width: 1920, height: 1080)   // 16:9
    private let portrait = CGSize(width: 1080, height: 1920)    // 9:16
    private let ultrawide = CGSize(width: 2520, height: 1080)   // 21:9

    /// Between B's load and B's first frame the retained frame is still A's,
    /// so the quad keeps A's crop. B's crop on A's frame would stretch about
    /// the middle third of A's height across a 16:10 display.
    func testRetainedFrameKeepsItsCropUntilTheNextVideosFirstFrame() throws {
        let display = CGSize(width: 2880, height: 1800)
        let a = WallpaperFrameCrop(videoSize: landscape, viewSize: display)
        XCTAssertNil(WallpaperFrameCrop.rebuild(a, forFrameOf: landscape, viewSize: display),
                     "Redrawing A's retained frame, playing or paused, keeps A's quad")

        let b = try XCTUnwrap(WallpaperFrameCrop.rebuild(a, forFrameOf: portrait, viewSize: display))
        XCTAssertEqual(b, WallpaperFrameCrop(videoSize: portrait, viewSize: display))
        XCTAssertEqual(a.textureRect.height, 1, accuracy: 0.0001)
        XCTAssertEqual(b.textureRect.height, (1080.0 / 1920.0) / (2880.0 / 1800.0), accuracy: 0.0001)
    }

    /// 16:9 → 21:9 on a 16:9 display: B's crop would squeeze A's full frame
    /// into about 76% of its width, which reads as 1.3× too wide.
    func testWiderNextVideoSwitchesCropOnlyWithItsOwnFrame() throws {
        let display = CGSize(width: 1920, height: 1080)
        let a = WallpaperFrameCrop(videoSize: landscape, viewSize: display)
        XCTAssertEqual(a.textureRect, CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertNil(WallpaperFrameCrop.rebuild(a, forFrameOf: landscape, viewSize: display))
        let b = try XCTUnwrap(WallpaperFrameCrop.rebuild(a, forFrameOf: ultrawide, viewSize: display))
        XCTAssertEqual(b.textureRect.width, (16.0 / 9.0) / (21.0 / 9.0), accuracy: 0.0001)
    }

    /// A drawable resize rebuilds the quad for the frame on screen, not for a
    /// video that has loaded but not yet delivered a frame.
    func testViewResizeRebuildsForTheDrawnFrame() {
        let a = WallpaperFrameCrop(videoSize: landscape, viewSize: CGSize(width: 1440, height: 900))
        let resized = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(WallpaperFrameCrop.rebuild(a, forFrameOf: landscape, viewSize: resized),
                       WallpaperFrameCrop(videoSize: landscape, viewSize: resized))
    }

    func testFirstFrameBuildsTheQuadAndSameAspectSwitchKeepsTheCrop() throws {
        let display = CGSize(width: 2560, height: 1440)
        let first = try XCTUnwrap(WallpaperFrameCrop.rebuild(nil, forFrameOf: landscape, viewSize: display))
        let smaller = try XCTUnwrap(WallpaperFrameCrop.rebuild(first, forFrameOf: CGSize(width: 1280, height: 720), viewSize: display))
        XCTAssertEqual(smaller.textureRect, first.textureRect)
    }
}
