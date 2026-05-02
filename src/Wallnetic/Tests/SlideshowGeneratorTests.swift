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
}
