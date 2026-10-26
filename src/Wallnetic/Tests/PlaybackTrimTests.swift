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

    func testStillFrameTimeStaysInsideTheRange() {
        let trim = PlaybackTrim(start: CMTime(value: 2, timescale: 1), end: CMTime(value: 5, timescale: 1),
                                fingerprint: fingerprint)
        XCTAssertEqual(trim.stillFrameTime(atOffset: 0.5), CMTime(value: 25, timescale: 10))
        XCTAssertEqual(trim.stillFrameTime(atOffset: -1), trim.start)
        XCTAssertEqual(trim.stillFrameTime(atOffset: .nan), trim.start)
        XCTAssertLessThan(trim.stillFrameTime(atOffset: 99), trim.end, "The still never comes from End or later")
        XCTAssertGreaterThanOrEqual(trim.stillFrameTime(atOffset: 99), trim.end - CMTime(value: 2, timescale: 600))
    }

    func testOptimizedCopyInheritsTheRangeOnItsOwnFrames() throws {
        let copyPrint = VideoFileFingerprint(byteSize: 5, modificationDate: Date(timeIntervalSinceReferenceDate: 1))
        let eighth = CMTime(value: 1, timescale: 8)
        let threeSeconds = CMTimeRange(start: .zero, duration: CMTime(value: 3, timescale: 1))
        let source = PlaybackTrim(start: CMTime(value: 11, timescale: 10), end: CMTime(value: 23, timescale: 10),
                                  fingerprint: fingerprint)
        let copy = try XCTUnwrap(source.inherited(byTrack: threeSeconds, frameDuration: eighth, fingerprint: copyPrint))
        XCTAssertEqual(copy.start, CMTime(value: 9, timescale: 8), "The first copy frame at or after Start")
        XCTAssertEqual(copy.end, CMTime(value: 19, timescale: 8))
        XCTAssertEqual(copy.fingerprint, copyPrint)

        let toEnd = PlaybackTrim(start: CMTime(value: 1, timescale: 1), end: CMTime(value: 3, timescale: 1),
                                 fingerprint: fingerprint)
        let shorter = CMTimeRange(start: .zero, duration: CMTime(value: 2_995, timescale: 1_000))
        XCTAssertEqual(toEnd.inherited(byTrack: shorter, frameDuration: eighth, fingerprint: copyPrint)?.end,
                       shorter.end, "End is clamped to a slightly shorter copy")
        let whole = PlaybackTrim(start: .zero, end: CMTime(value: 2_995, timescale: 1_000), fingerprint: fingerprint)
        XCTAssertNil(whole.inherited(byTrack: threeSeconds, frameDuration: eighth, fingerprint: copyPrint),
                     "A range covering the whole copy stores no trim")

        // The user cut only the last source frame (24 fps x 101). The copy at
        // 15 fps ends with a short sample showing that frame; End stays before it.
        let lastCut = PlaybackTrim(start: CMTime(value: 10, timescale: 24), end: CMTime(value: 100, timescale: 24),
                                   fingerprint: fingerprint)
        let fifteenth = CMTime(value: 1, timescale: 15)
        let copyTrack = CMTimeRange(start: .zero, duration: CMTime(value: 252_500, timescale: 60_000))
        let keptCut = try XCTUnwrap(lastCut.inherited(byTrack: copyTrack, frameDuration: fifteenth, fingerprint: copyPrint))
        XCTAssertEqual(keptCut.start, CMTime(value: 7, timescale: 15))
        XCTAssertEqual(keptCut.end, CMTime(value: 63, timescale: 15), "The cut frame's sliver is not kept")

        // Snapping both ends up to a 0.3 s grid leaves a 1 s range 0.9 s long:
        // End widens by one copy frame, or Start moves back at the copy's end.
        let tenths = CMTime(value: 3, timescale: 10)
        let minimum = PlaybackTrim(start: CMTime(value: 1, timescale: 10), end: CMTime(value: 11, timescale: 10),
                                   fingerprint: fingerprint)
        let widened = try XCTUnwrap(minimum.inherited(byTrack: threeSeconds, frameDuration: tenths, fingerprint: copyPrint))
        XCTAssertEqual(widened.start, CMTime(value: 3, timescale: 10))
        XCTAssertEqual(widened.end, CMTime(value: 15, timescale: 10))
        let lastSecond = PlaybackTrim(start: CMTime(value: 2, timescale: 1), end: CMTime(value: 3, timescale: 1),
                                      fingerprint: fingerprint)
        let movedBack = try XCTUnwrap(lastSecond.inherited(byTrack: threeSeconds, frameDuration: tenths,
                                                           fingerprint: copyPrint))
        XCTAssertEqual(movedBack.start, CMTime(value: 18, timescale: 10))
        XCTAssertEqual(movedBack.end, CMTime(value: 3, timescale: 1))
        XCTAssertNil(lastSecond.inherited(byTrack: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 2)),
                                          frameDuration: tenths, fingerprint: copyPrint),
                     "A copy shorter than the minimum keeps no range")
    }

    func testUnbuiltMarksClearWhenTheRangeIsEdited() throws {
        let suite = "PlaybackTrimStoreMarks.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PlaybackTrimStore(defaults: defaults)
        let url = URL(fileURLWithPath: "/tmp/library/a.mp4")
        try store.setTrim(PlaybackTrim(start: .zero, end: CMTime(value: 2, timescale: 1), fingerprint: fingerprint),
                          for: url)
        store.noteTrim(applied: false, for: URL(fileURLWithPath: "/tmp/library/./a.mp4"))
        XCTAssertTrue(store.isUnbuilt(url))
        store.noteTrim(applied: true, for: url)
        XCTAssertFalse(store.isUnbuilt(url))
        store.noteTrim(applied: false, for: url)
        try store.setTrim(nil, for: url)
        XCTAssertFalse(store.isUnbuilt(url), "An edit clears the mark until the next load reports")
        store.noteTrim(applied: false, for: url)
        XCTAssertTrue(PlaybackTrimStore(defaults: defaults).unbuiltPaths.isEmpty, "Marks are not saved")
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
