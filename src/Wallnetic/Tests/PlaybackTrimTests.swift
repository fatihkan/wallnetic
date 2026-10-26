import XCTest
import CoreMedia
@testable import Wallnetic

final class PlaybackTrimTests: XCTestCase {
    private let fingerprint = VideoFileFingerprint(byteSize: 1_000, modificationDate: Date(timeIntervalSinceReferenceDate: 800_000_000.25))
    private let duration = CMTime(value: 300, timescale: 30) // 10 s

    func testSelectionKeepsExactTimesAndStoresNoTrimForTheWholeVideo() throws {
        let start = CMTime(value: 1001, timescale: 30000)
        let end = CMTime(value: 150150, timescale: 30000)
        let trim = try XCTUnwrap(PlaybackTrim.selection(start: start, end: end, duration: duration, fingerprint: fingerprint))
        XCTAssertEqual(trim.start.value, 1001)
        XCTAssertEqual(trim.start.timescale, 30000)
        XCTAssertEqual(trim.end.value, 150150)
        XCTAssertNil(try PlaybackTrim.selection(start: .zero, end: duration, duration: duration, fingerprint: fingerprint))
        let short = CMTime(value: 1, timescale: 2)
        XCTAssertNil(try PlaybackTrim.selection(start: .zero, end: short, duration: short, fingerprint: fingerprint),
                     "A full selection of a video shorter than the minimum is the whole video, not an error")
    }

    func testSelectionRejectsRangesOutsideTheVideoOrShorterThanTheMinimum() {
        let second = CMTime(value: 1, timescale: 1)
        let cases: [(CMTime, CMTime, PlaybackTrimError)] = [
            (CMTime(value: -1, timescale: 30), second, .outsideVideo),
            (second, duration + CMTime(value: 1, timescale: 30), .outsideVideo),
            (second + second, second, .outsideVideo),
            (second, second, .outsideVideo),
            (second, CMTime(value: 59, timescale: 30), .tooShort),
            (.invalid, second, .invalidTime),
            (.zero, .positiveInfinity, .invalidTime),
        ]
        for (start, end, expected) in cases {
            XCTAssertThrowsError(try PlaybackTrim.selection(start: start, end: end, duration: duration,
                                                            fingerprint: fingerprint)) { error in
                XCTAssertEqual(error as? PlaybackTrimError, expected, "\(start.seconds)–\(end.seconds)")
            }
        }
        XCTAssertNoThrow(try PlaybackTrim.selection(start: second, end: second + second, duration: duration,
                                                    fingerprint: fingerprint), "Exactly the minimum length is allowed")
    }

    func testRangeAppliesOnlyInsideTheLoadedTrack() throws {
        let trim = PlaybackTrim(start: CMTime(value: 2, timescale: 1), end: CMTime(value: 5, timescale: 1),
                                fingerprint: fingerprint)
        let track = CMTimeRange(start: .zero, duration: duration)
        XCTAssertEqual(trim.timeRange(within: track), CMTimeRange(start: trim.start, end: trim.end))

        let atEnd = PlaybackTrim(start: CMTime(value: 8, timescale: 1), end: CMTime(value: 10005, timescale: 1000),
                                 fingerprint: fingerprint)
        XCTAssertEqual(atEnd.timeRange(within: track)?.end, duration,
                       "An End a few milliseconds past the track end is clamped to it")
        let past = PlaybackTrim(start: CMTime(value: 8, timescale: 1), end: CMTime(value: 1003, timescale: 100),
                                fingerprint: fingerprint)
        XCTAssertNil(past.timeRange(within: track))
        let shorterTrack = CMTimeRange(start: .zero, duration: CMTime(value: 4, timescale: 1))
        XCTAssertNil(trim.timeRange(within: shorterTrack), "A range outside the loaded duration plays the full video")
        let lateTrack = CMTimeRange(start: CMTime(value: 3, timescale: 1), duration: duration)
        XCTAssertNil(trim.timeRange(within: lateTrack))
        let clampedTooShort = PlaybackTrim(start: CMTime(value: 95, timescale: 10), end: CMTime(value: 10005, timescale: 1000),
                                           fingerprint: fingerprint)
        XCTAssertNil(clampedTooShort.timeRange(within: track))
        XCTAssertNil(trim.timeRange(within: .invalid))
    }

    /// A nanosecond Start and a 1/600 s track end cannot share a timescale, so
    /// `CMTimeRange` rounds its duration. The range must still end inside the
    /// track, or the composition insert and the preview looper reject it.
    func testRangeEndsInsideTheTrackWithMixedTimescales() throws {
        let start = CMTime(value: 333_333_330, timescale: 1_000_000_000)
        let trackEnd = CMTime(value: 2_419, timescale: 600)
        let range = PlaybackTrim.range(from: start, to: trackEnd, notAfter: trackEnd)
        XCTAssertEqual(range.start, start)
        XCTAssertLessThanOrEqual(range.end, trackEnd)
        XCTAssertLessThan(trackEnd - range.end, CMTime(value: 2, timescale: 1_000_000_000))
        let trim = PlaybackTrim(start: start, end: trackEnd, fingerprint: fingerprint)
        let fitted = try XCTUnwrap(trim.timeRange(within: CMTimeRange(start: .zero, end: trackEnd)))
        XCTAssertLessThanOrEqual(fitted.end, trackEnd)
    }

    func testFrameAlignmentUsesTheTracksOwnFrameTiming() {
        let ntsc = CMTime(value: 1001, timescale: 30000)
        XCTAssertEqual(PlaybackTrim.aligned(CMTime(value: 1, timescale: 1), frameDuration: ntsc),
                       CMTime(value: 30030, timescale: 30000), "1 s rounds to frame 30 at 29.97 fps")
        XCTAssertEqual(PlaybackTrim.aligned(CMTime(value: 1016, timescale: 1000), frameDuration: ntsc),
                       CMTime(value: 30030, timescale: 30000))
        let origin = CMTime(value: 1, timescale: 10)
        XCTAssertEqual(PlaybackTrim.aligned(CMTime(value: 33, timescale: 100), frameDuration: CMTime(value: 1, timescale: 10),
                                            origin: origin), CMTime(value: 3, timescale: 10))
        XCTAssertEqual(PlaybackTrim.aligned(CMTime(value: 7, timescale: 4), frameDuration: .zero),
                       CMTime(value: 7, timescale: 4), "Without a frame duration the time is kept")
        XCTAssertFalse(PlaybackTrim.aligned(.invalid, frameDuration: ntsc).isNumeric)
    }

    func testFingerprintMismatchMeansADifferentFile() throws {
        let trim = PlaybackTrim(start: .zero, end: CMTime(value: 2, timescale: 1), fingerprint: fingerprint)
        XCTAssertTrue(trim.matches(fingerprint))
        XCTAssertFalse(trim.matches(nil))
        XCTAssertFalse(trim.matches(VideoFileFingerprint(byteSize: 1_001, modificationDate: fingerprint.modificationDate)))
        XCTAssertFalse(trim.matches(VideoFileFingerprint(byteSize: 1_000, modificationDate: fingerprint.modificationDate.addingTimeInterval(1))))

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("fingerprint-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertNil(VideoFileFingerprint(fileAt: file))
        try Data(count: 10).write(to: file)
        let first = try XCTUnwrap(VideoFileFingerprint(fileAt: file))
        XCTAssertEqual(first.byteSize, 10)
        XCTAssertEqual(VideoFileFingerprint(fileAt: file), first)
        try Data(count: 12).write(to: file)
        XCTAssertNotEqual(VideoFileFingerprint(fileAt: file), first, "A replaced file does not inherit the range")
        XCTAssertNil(TrimmedVideoAsset.usableTrim(PlaybackTrim(start: .zero, end: CMTime(value: 2, timescale: 1),
                                                               fingerprint: first), for: file))
    }

    func testCodingKeepsExactTimesAndRejectsBackwardRanges() throws {
        let trim = PlaybackTrim(start: CMTime(value: 1001, timescale: 30000), end: CMTime(value: 7, timescale: 2),
                                fingerprint: fingerprint)
        let decoded = try JSONDecoder().decode(PlaybackTrim.self, from: JSONEncoder().encode(trim))
        XCTAssertEqual(decoded, trim)
        XCTAssertEqual(decoded.start.timescale, 30000)
        XCTAssertEqual(decoded.fingerprint, fingerprint)

        for (startTimescale, endValue) in [(0, 7), (30000, 0)] {
            let json = """
            {"startValue":1001,"startTimescale":\(startTimescale),"endValue":\(endValue),"endTimescale":2,
             "fingerprint":{"byteSize":1000,"modificationDate":800000000.25}}
            """
            XCTAssertThrowsError(try JSONDecoder().decode(PlaybackTrim.self, from: Data(json.utf8)))
        }
    }

    func testStoreKeepsRangesPerStandardizedPathAndRemovesThem() throws {
        let suite = "PlaybackTrimStore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PlaybackTrimStore(defaults: defaults)
        let beach = URL(fileURLWithPath: "/tmp/library/beach.mp4")
        let kept = URL(fileURLWithPath: "/tmp/library/kept.mp4")
        let trim = PlaybackTrim(start: CMTime(value: 1, timescale: 1), end: CMTime(value: 3, timescale: 1),
                                fingerprint: fingerprint)
        try store.setTrim(trim, for: URL(fileURLWithPath: "/tmp/library/../library/beach.mp4"))
        try store.setTrim(trim, for: kept)
        XCTAssertEqual(store.trim(for: beach), trim)
        XCTAssertEqual(PlaybackTrimStore(defaults: defaults).trim(for: beach), trim, "Ranges survive relaunch")

        try store.setTrim(nil, for: beach)
        XCTAssertNil(PlaybackTrimStore(defaults: defaults).trim(for: beach))
        try store.setTrim(trim, for: beach)
        store.removeTrims(for: [URL(fileURLWithPath: "/tmp/./library/beach.mp4")])
        let relaunched = PlaybackTrimStore(defaults: defaults)
        XCTAssertNil(relaunched.trim(for: beach), "Removal paths are standardized like the stored keys")
        XCTAssertEqual(relaunched.trim(for: kept), trim, "Only the removed item's range is forgotten")
    }

    func testUnreadableRangesAreKeptAsARecoveryBackup() throws {
        let suite = "PlaybackTrimStoreCorrupt.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let corrupt = Data(#"{"version":1,"trims":{"/tmp/a.mp4":{"startValue":5}}}"#.utf8)
        defaults.set(corrupt, forKey: PlaybackTrimStore.key)

        let store = PlaybackTrimStore(defaults: defaults)
        XCTAssertTrue(store.isUnreadable)
        XCTAssertTrue(store.trims.isEmpty, "Unreadable ranges never apply")
        store.removeTrims(for: [URL(fileURLWithPath: "/tmp/a.mp4")])
        XCTAssertEqual(defaults.data(forKey: PlaybackTrimStore.key), corrupt, "Pruning nothing does not overwrite saved data")
        XCTAssertNil(defaults.object(forKey: PlaybackTrimStore.key + ".recoveryBackup"))

        let trim = PlaybackTrim(start: .zero, end: CMTime(value: 2, timescale: 1), fingerprint: fingerprint)
        try store.setTrim(trim, for: URL(fileURLWithPath: "/tmp/b.mp4"))
        XCTAssertEqual(defaults.data(forKey: PlaybackTrimStore.key + ".recoveryBackup"), corrupt)
        XCTAssertFalse(store.isUnreadable)
        XCTAssertEqual(PlaybackTrimStore(defaults: defaults).trim(for: URL(fileURLWithPath: "/tmp/b.mp4")), trim)

        defaults.set(Data(#"{"version":2,"trims":{}}"#.utf8), forKey: PlaybackTrimStore.key)
        XCTAssertTrue(PlaybackTrimStore(defaults: defaults).isUnreadable, "A newer format is not misread")
    }
}
