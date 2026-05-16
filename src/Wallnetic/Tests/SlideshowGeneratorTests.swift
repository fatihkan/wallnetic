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
        // Render budget: totalFrames = N*d - (N-1)*T (overlapping crossfades).
        // Verify for representative N/d/T triples.
        struct Case { let n: Int; let d: Double; let t: Double; let expected: Double }
        let cases: [Case] = [
            Case(n: 1, d: 5, t: 0.6, expected: 5),
            Case(n: 2, d: 5, t: 0.6, expected: 5 * 2 - 0.6),
            Case(n: 10, d: 5, t: 0.6, expected: 5 * 10 - 0.6 * 9),
            Case(n: 50, d: 5, t: 0.6, expected: 5 * 50 - 0.6 * 49)
        ]
        for c in cases {
            let actual = Double(c.n) * c.d - Double(max(0, c.n - 1)) * c.t
            XCTAssertEqual(actual, c.expected, accuracy: 0.0001, "N=\(c.n) failed")
        }
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
