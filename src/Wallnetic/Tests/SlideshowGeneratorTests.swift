import XCTest
import Photos
@testable import Wallnetic

/// `SlideshowGenerator` — math + cancellation (#137 / #166).
/// Full pixel-buffer render is out of scope (requires real PHAssets); these
/// tests guard the configuration shape that bit us in the post-merge review.
final class SlideshowGeneratorTests: XCTestCase {
    func testNoAssetsThrowsNoAssetsError() async {
        let gen = SlideshowGenerator()
        do {
            _ = try await gen.generate(
                assets: [],
                settings: SlideshowGenerator.Settings(),
                progress: { _ in }
            )
            XCTFail("Expected noAssets error")
        } catch SlideshowGenerator.GeneratorError.noAssets {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testResolutionSizesAreEvenForH264() {
        // H.264 requires even dimensions — the resolution presets must
        // satisfy this without per-call rounding.
        for resolution in [
            SlideshowGenerator.Resolution.hd1080,
            SlideshowGenerator.Resolution.qhd1440,
            SlideshowGenerator.Resolution.uhd4k
        ] {
            let size = resolution.size
            XCTAssertEqual(Int(size.width) % 2, 0, "Width odd for \(resolution)")
            XCTAssertEqual(Int(size.height) % 2, 0, "Height odd for \(resolution)")
        }
    }

    func testBitratesScaleWithResolution() {
        XCTAssertLessThan(SlideshowGenerator.Resolution.hd1080.bitrate,
                          SlideshowGenerator.Resolution.qhd1440.bitrate)
        XCTAssertLessThan(SlideshowGenerator.Resolution.qhd1440.bitrate,
                          SlideshowGenerator.Resolution.uhd4k.bitrate)
    }

    func testSettingsDefaults() {
        let s = SlideshowGenerator.Settings()
        XCTAssertEqual(s.perPhotoDuration, 5.0)
        XCTAssertEqual(s.transitionDuration, 0.6)
        XCTAssertTrue(s.kenBurns)
        XCTAssertEqual(s.fps, 30)
    }

    // MARK: - P3-15: bounds fuzz

    func testFrameCountFormula() {
        // YUKSEK-2: drive the actual SUT (totalFrames helper) instead of
        // re-deriving the formula in-test. A regression in the renderer
        // would now fail this test.
        let fps = 30
        let perPhoto = 5.0
        let transition = 0.6
        var s = SlideshowGenerator.Settings()
        s.perPhotoDuration = perPhoto
        s.transitionDuration = transition
        s.fps = Int32(fps)
        s.transition = .crossfade

        let framesPerImage = Int(perPhoto * Double(fps))
        let transitionFrames = min(Int(transition * Double(fps)), framesPerImage / 2)

        let cases: [Int] = [0, 1, 2, 10, 50]
        for n in cases {
            let expected = n == 0 ? 0 : n * framesPerImage - transitionFrames * (n - 1)
            let actual = SlideshowGenerator.totalFrames(assetCount: n, settings: s)
            XCTAssertEqual(actual, expected, "N=\(n) failed")
        }
    }

    func testTotalFramesZeroForEmptyInput() {
        let s = SlideshowGenerator.Settings()
        XCTAssertEqual(SlideshowGenerator.totalFrames(assetCount: 0, settings: s), 0)
    }

    func testTotalFramesNoTransitionMode() {
        var s = SlideshowGenerator.Settings()
        s.transition = .none
        // No transition → frames are pure N × framesPerImage.
        let fps = Int(s.fps)
        let framesPerImage = Int(s.perPhotoDuration * Double(fps))
        XCTAssertEqual(
            SlideshowGenerator.totalFrames(assetCount: 5, settings: s),
            5 * framesPerImage
        )
    }

    func testTransitionBoundedByPerPhotoDuration() {
        // If T >= d, frames math breaks. Verify our defaults respect it
        // and that we'd ideally clamp T at the call site.
        let s = SlideshowGenerator.Settings()
        XCTAssertLessThan(s.transitionDuration, s.perPhotoDuration,
                          "Transition must be shorter than per-photo duration.")
    }

    func testResolutionWidthHeightArePositive() {
        for r in [SlideshowGenerator.Resolution.hd1080, .qhd1440, .uhd4k] {
            XCTAssertGreaterThan(r.size.width, 0)
            XCTAssertGreaterThan(r.size.height, 0)
        }
    }
}
