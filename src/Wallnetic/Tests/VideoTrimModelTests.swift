import XCTest
import AVFoundation
import CoreMedia
@testable import Wallnetic

/// #309: the trim sheet's draft range, saving rules and Library status.
@MainActor
final class VideoTrimModelTests: XCTestCase {
    private func seconds(_ value: Double) -> CMTime { CMTime(seconds: value, preferredTimescale: 600) }

    func testEditsSnapToFramesAndKeepTheMinimumLength() async throws {
        let fixture = try await Fixture(frames: 30)
        defer { fixture.remove() }
        let model = VideoTrimModel(wallpaper: Wallpaper(url: fixture.video), store: fixture.store, isInLibrary: { _ in true })
        defer { model.stopPreview() }
        await model.load()
        XCTAssertEqual(model.state, .ready)
        XCTAssertEqual(model.start, .zero)
        XCTAssertEqual(model.end, CMTime(value: 3, timescale: 1))
        XCTAssertTrue(model.isFullVideo)

        model.setStart(seconds(1.04))
        XCTAssertEqual(model.start, CMTime(value: 1, timescale: 1), "Start snaps to the nearest frame")
        model.setEnd(seconds(1.5))
        XCTAssertEqual(model.end, CMTime(value: 2, timescale: 1), "A loop keeps at least one second")
        model.stepEnd(frames: 1)
        XCTAssertEqual(model.end, CMTime(value: 21, timescale: 10))
        model.stepStart(frames: 2)
        XCTAssertEqual(model.start, CMTime(value: 11, timescale: 10), "Start stops one second before End")
        model.setEnd(seconds(2.97))
        XCTAssertEqual(model.end, CMTime(value: 3, timescale: 1), "Near the end, End is the end of the video")
        model.stepEnd(frames: -1)
        XCTAssertEqual(model.end, CMTime(value: 29, timescale: 10))
        XCTAssertEqual(model.length, CMTime(value: 18, timescale: 10))
        model.resetToFullVideo()
        XCTAssertTrue(model.isFullVideo)
    }

    func testSaveStoresTheRangeAndAFullSelectionRemovesIt() async throws {
        let fixture = try await Fixture(frames: 30)
        defer { fixture.remove() }
        let model = VideoTrimModel(wallpaper: Wallpaper(url: fixture.video), store: fixture.store, isInLibrary: { _ in true })
        defer { model.stopPreview() }
        await model.load()
        model.setStart(seconds(1))
        model.setEnd(seconds(2))
        XCTAssertTrue(model.save())
        let stored = try XCTUnwrap(fixture.store.trim(for: fixture.video))
        XCTAssertEqual(stored.start, CMTime(value: 1, timescale: 1))
        XCTAssertEqual(stored.end, CMTime(value: 2, timescale: 1))
        XCTAssertEqual(stored.fingerprint, VideoFileFingerprint(fileAt: fixture.video))

        let reopened = VideoTrimModel(wallpaper: Wallpaper(url: fixture.video), store: fixture.store, isInLibrary: { _ in true })
        defer { reopened.stopPreview() }
        await reopened.load()
        XCTAssertEqual(reopened.start, stored.start, "Edit Trim opens on the saved range")
        XCTAssertEqual(reopened.end, stored.end)
        reopened.setStart(seconds(0.5))
        XCTAssertEqual(fixture.store.trim(for: fixture.video), stored, "Editing without Save keeps the stored range")
        reopened.resetToFullVideo()
        XCTAssertTrue(reopened.save())
        XCTAssertNil(fixture.store.trim(for: fixture.video), "A full-length selection removes the trim")
    }

    func testSavingAfterRemovalOrReplacementStoresNothing() async throws {
        let fixture = try await Fixture(frames: 30)
        defer { fixture.remove() }
        var inLibrary = true
        let model = VideoTrimModel(wallpaper: Wallpaper(url: fixture.video), store: fixture.store,
                                   isInLibrary: { _ in inLibrary })
        defer { model.stopPreview() }
        await model.load()
        model.setStart(seconds(1))

        inLibrary = false
        XCTAssertFalse(model.save())
        XCTAssertEqual(model.error, "This video is no longer in the Library, so nothing was saved.")
        XCTAssertNil(fixture.store.trim(for: fixture.video))

        inLibrary = true
        try await Fixture.writeVideo(to: fixture.video, frames: 40)
        XCTAssertFalse(model.save())
        XCTAssertTrue(model.error?.contains("changed while the editor was open") == true)
        XCTAssertNil(fixture.store.trim(for: fixture.video))
    }

    func testARangeForADifferentFileIsReportedAndNotApplied() async throws {
        let fixture = try await Fixture(frames: 30)
        defer { fixture.remove() }
        let stale = PlaybackTrim(start: CMTime(value: 1, timescale: 1), end: CMTime(value: 2, timescale: 1),
                                 fingerprint: VideoFileFingerprint(byteSize: 1, modificationDate: .distantPast))
        try fixture.store.setTrim(stale, for: fixture.video)
        let model = VideoTrimModel(wallpaper: Wallpaper(url: fixture.video), store: fixture.store, isInLibrary: { _ in true })
        defer { model.stopPreview() }
        await model.load()
        XCTAssertTrue(model.isFullVideo, "A range for another file is not shown as the selection")
        XCTAssertNotNil(model.note)

        XCTAssertEqual(LoopRangeStatus(trim: nil, fileAt: fixture.video, duration: 3), .none)
        XCTAssertEqual(LoopRangeStatus(trim: stale, fileAt: fixture.video, duration: 3), .notApplied)
        let fingerprint = try XCTUnwrap(VideoFileFingerprint(fileAt: fixture.video))
        let current = PlaybackTrim(start: CMTime(value: 1, timescale: 1), end: CMTime(value: 2, timescale: 1),
                                   fingerprint: fingerprint)
        let status = LoopRangeStatus(trim: current, fileAt: fixture.video, duration: 3)
        XCTAssertEqual(status, .applied(current))
        XCTAssertEqual(LoopRangeStatus.durationText(status, duration: 3), "0:01 of 0:03")
        XCTAssertEqual(LoopRangeStatus.durationText(.notApplied, duration: 3), "0:03")
        XCTAssertEqual(LoopRangeStatus(trim: current, fileAt: fixture.video, duration: 1.5), .notApplied,
                       "A range past the video's end does not apply")
    }

    func testAVideoShorterThanTheMinimumCanOnlyLoopInFull() async throws {
        let fixture = try await Fixture(frames: 5)
        defer { fixture.remove() }
        let model = VideoTrimModel(wallpaper: Wallpaper(url: fixture.video), store: fixture.store, isInLibrary: { _ in true })
        defer { model.stopPreview() }
        await model.load()
        model.setStart(seconds(0.2))
        model.setEnd(seconds(0.3))
        XCTAssertTrue(model.isFullVideo)
        XCTAssertTrue(model.save())
        XCTAssertNil(fixture.store.trim(for: fixture.video))
    }

    /// Clamping rounds up or down to a frame; times on the grid stay put
    /// despite floating-point error.
    func testFrameGridRoundingRules() {
        let frame = CMTime(value: 1, timescale: 10)
        let onGrid = CMTime(value: 2, timescale: 1)
        XCTAssertEqual(PlaybackTrim.aligned(onGrid, frameDuration: frame, rule: .up), onGrid)
        XCTAssertEqual(PlaybackTrim.aligned(onGrid, frameDuration: frame, rule: .down), onGrid)
        let between = CMTime(value: 205, timescale: 100)
        XCTAssertEqual(PlaybackTrim.aligned(between, frameDuration: frame, rule: .up), CMTime(value: 21, timescale: 10))
        XCTAssertEqual(PlaybackTrim.aligned(between, frameDuration: frame, rule: .down), onGrid)
        let ntsc = CMTime(value: 1001, timescale: 30000)
        let thirtyFrames = CMTime(value: 30030, timescale: 30000)
        XCTAssertEqual(PlaybackTrim.aligned(thirtyFrames, frameDuration: ntsc, rule: .up), thirtyFrames)
        XCTAssertEqual(PlaybackTrim.aligned(thirtyFrames, frameDuration: ntsc, rule: .down), thirtyFrames)
    }

    /// Variable frame rate: Start and End snap and step to the video's own
    /// frames, not to a grid of its shortest frame.
    func testVariableFrameRateStepsMoveToRealFrames() async throws {
        var ticks: Int64 = 0
        var times: [CMTime] = []
        for index in 0..<30 {
            times.append(CMTime(value: ticks, timescale: 600))
            ticks += [30, 60, 90][index % 3]
        }
        let fixture = try await Fixture(times: times, end: CMTime(value: ticks, timescale: 600))
        defer { fixture.remove() }
        let model = VideoTrimModel(wallpaper: Wallpaper(url: fixture.video), store: fixture.store, isInLibrary: { _ in true })
        defer { model.stopPreview() }
        await model.load()
        XCTAssertTrue(model.hasExactFrames)
        XCTAssertEqual(model.frameStarts, times)
        model.stepStart(frames: 1)
        XCTAssertEqual(model.start, CMTime(value: 30, timescale: 600))
        model.stepStart(frames: 1)
        XCTAssertEqual(model.start, CMTime(value: 90, timescale: 600), "Each step reaches the next frame")
        model.setStart(CMTime(value: 2, timescale: 10))
        XCTAssertEqual(model.start, CMTime(value: 90, timescale: 600), "0.2 s is nearest to the frame at 0.15 s")
        model.stepEnd(frames: -1)
        XCTAssertEqual(model.end, CMTime(value: 1710, timescale: 600), "End steps back to the last frame's start")
        XCTAssertTrue(model.save())
        let stored = try XCTUnwrap(fixture.store.trim(for: fixture.video))
        XCTAssertEqual(stored.start, CMTime(value: 90, timescale: 600))
        XCTAssertEqual(stored.end, CMTime(value: 1710, timescale: 600))
    }

    /// A video track that starts after an empty edit: its first frame, not
    /// the track's start, is where the video begins, and frames map through
    /// the edit into the file's timeline.
    func testALeadingEmptyEditStartsTheVideoAtItsFirstFrame() async throws {
        let fixture = try await Fixture(times: (5..<25).map { CMTime(value: Int64($0), timescale: 10) },
                                        end: CMTime(value: 25, timescale: 10))
        defer { fixture.remove() }
        let model = VideoTrimModel(wallpaper: Wallpaper(url: fixture.video), store: fixture.store, isInLibrary: { _ in true })
        defer { model.stopPreview() }
        await model.load()
        XCTAssertTrue(model.hasExactFrames)
        XCTAssertEqual(model.origin, CMTime(value: 5, timescale: 10))
        XCTAssertEqual(model.frameStarts?.first, CMTime(value: 5, timescale: 10))
        XCTAssertTrue(model.isFullVideo)
        model.setStart(CMTime(value: 94, timescale: 100))
        XCTAssertEqual(model.start, CMTime(value: 9, timescale: 10), "Start lands on a real frame")
        XCTAssertTrue(model.save())
        XCTAssertEqual(fixture.store.trim(for: fixture.video)?.start, CMTime(value: 9, timescale: 10))
    }

    func testFrameBoundariesMapThroughEditsAndFindNeighbours() throws {
        let media = (0..<4).map { CMTime(value: Int64($0), timescale: 10) }
        let shifted = CMTimeMapping(source: CMTimeRange(start: .zero, duration: CMTime(value: 4, timescale: 10)),
                                    target: CMTimeRange(start: CMTime(value: 5, timescale: 10),
                                                        duration: CMTime(value: 4, timescale: 10)))
        XCTAssertEqual(FrameBoundaries.layout(ofMediaTimes: media, edits: [.init(mapping: shifted, isEmpty: false)])?
                        .frameStarts, (5..<9).map { CMTime(value: Int64($0), timescale: 10) })
        let slowed = CMTimeMapping(source: shifted.source,
                                   target: CMTimeRange(start: .zero, duration: CMTime(value: 8, timescale: 10)))
        XCTAssertNil(FrameBoundaries.layout(ofMediaTimes: media, edits: [.init(mapping: slowed, isEmpty: false)]),
                     "A speed change is not exact")
        XCTAssertEqual(FrameBoundaries.layout(ofMediaTimes: media.reversed(), edits: [])?.frameStarts, media)

        // A cut that keeps [0, 1 s) and [2.01 s, 4 s) of a 30 fps clip: the
        // second edit starts inside frame 60, which is shown from 1 s.
        let frame = { (index: Int64) in CMTime(value: index, timescale: 30) }
        let clip = (0..<120).map { frame(Int64($0)) }
        let cutPoint = CMTime(value: 201, timescale: 100)
        let cut: [FrameBoundaries.Edit] = [
            .init(mapping: CMTimeMapping(source: CMTimeRange(start: .zero, end: frame(30)),
                                         target: CMTimeRange(start: .zero, end: frame(30))), isEmpty: false),
            .init(mapping: CMTimeMapping(source: CMTimeRange(start: cutPoint, end: frame(120)),
                                         target: CMTimeRange(start: frame(30), duration: frame(120) - cutPoint)),
                  isEmpty: false),
        ]
        let cutLayout = try XCTUnwrap(FrameBoundaries.layout(ofMediaTimes: clip, edits: cut))
        XCTAssertTrue(cutLayout.frameStarts.contains(frame(30)), "The second edit's start is a frame start")
        XCTAssertTrue(cutLayout.frameStarts.contains(frame(30) + (frame(61) - cutPoint)))
        XCTAssertTrue(cutLayout.gapStarts.isEmpty)

        // An empty edit at 1 s: its start can end a loop, but no frame starts there.
        let gapped: [FrameBoundaries.Edit] = [
            .init(mapping: CMTimeMapping(source: CMTimeRange(start: .zero, end: frame(30)),
                                         target: CMTimeRange(start: .zero, end: frame(30))), isEmpty: false),
            .init(mapping: CMTimeMapping(source: .invalid,
                                         target: CMTimeRange(start: frame(30), duration: CMTime(value: 1, timescale: 2))),
                  isEmpty: true),
            .init(mapping: CMTimeMapping(source: CMTimeRange(start: frame(30), end: frame(60)),
                                         target: CMTimeRange(start: CMTime(value: 3, timescale: 2), duration: frame(30))),
                  isEmpty: false),
        ]
        let gapLayout = try XCTUnwrap(FrameBoundaries.layout(ofMediaTimes: clip, edits: gapped))
        XCTAssertEqual(gapLayout.gapStarts, [frame(30)])
        XCTAssertFalse(gapLayout.frameStarts.contains(frame(30)))
        XCTAssertTrue(gapLayout.frameStarts.contains(CMTime(value: 3, timescale: 2)))

        let sorted = [0, 5, 15, 30].map { CMTime(value: Int64($0), timescale: 100) }
        XCTAssertEqual(FrameBoundaries.nearest(to: CMTime(value: 9, timescale: 100), in: sorted), sorted[1])
        XCTAssertEqual(FrameBoundaries.nearest(to: CMTime(value: 11, timescale: 100), in: sorted), sorted[2])
        XCTAssertEqual(FrameBoundaries.nearest(to: CMTime(value: 99, timescale: 100), in: sorted), sorted[3])
        XCTAssertEqual(FrameBoundaries.first(notBefore: CMTime(value: 6, timescale: 100), in: sorted), sorted[2])
        XCTAssertEqual(FrameBoundaries.first(notBefore: CMTime(value: 15, timescale: 100), in: sorted), sorted[2])
        XCTAssertNil(FrameBoundaries.first(notBefore: CMTime(value: 31, timescale: 100), in: sorted))
        XCTAssertEqual(FrameBoundaries.last(notAfter: CMTime(value: 14, timescale: 100), in: sorted), sorted[1])
        XCTAssertEqual(FrameBoundaries.last(notAfter: CMTime(value: 15, timescale: 100), in: sorted), sorted[2])
        XCTAssertNil(FrameBoundaries.last(notAfter: CMTime(value: -1, timescale: 100), in: sorted))
    }

    /// With very fine timescales the on-grid snap must not round a result to
    /// the wrong side, or a clamped loop could fall below one second.
    func testRoundingNeverCrossesTheRequestedSide() {
        let frame = CMTime(value: 33_333_333, timescale: 1_000_000_000)
        for index in stride(from: 1, through: 2_000, by: 7) {
            let boundary = CMTimeMultiply(frame, multiplier: Int32(index))
            for time in [boundary, boundary - CMTime(value: 10, timescale: 1_000_000_000),
                         boundary + CMTime(value: 10, timescale: 1_000_000_000)] {
                XCTAssertLessThanOrEqual(PlaybackTrim.aligned(time, frameDuration: frame, rule: .down), time)
                XCTAssertGreaterThanOrEqual(PlaybackTrim.aligned(time, frameDuration: frame, rule: .up), time)
            }
        }
        let end = CMTimeMultiply(frame, multiplier: 60)
        let latest = PlaybackTrim.aligned(end - PlaybackTrim.minimumLength, frameDuration: frame, rule: .down)
        XCTAssertGreaterThanOrEqual(end - latest, PlaybackTrim.minimumLength)
    }

    /// Frames timed in nanoseconds, a track that ends in 1/600 s units: a
    /// reopened range keeps its exact End, so Save and a full-length reset work.
    func testReopeningANanosecondTimescaleRangeKeepsItsExactEnd() async throws {
        let frame = CMTime(value: 33_333_333, timescale: 1_000_000_000)
        let times = (0..<121).map { CMTimeMultiply(frame, multiplier: Int32($0)) }
        let fixture = try await Fixture(times: times, end: CMTimeMultiply(frame, multiplier: 121),
                                        mediaTimeScale: 1_000_000_000)
        defer { fixture.remove() }
        let model = VideoTrimModel(wallpaper: Wallpaper(url: fixture.video), store: fixture.store, isInLibrary: { _ in true })
        defer { model.stopPreview() }
        await model.load()
        model.stepStart(frames: 10)
        XCTAssertTrue(model.save(), model.error ?? "")
        let stored = try XCTUnwrap(fixture.store.trim(for: fixture.video))
        XCTAssertEqual(stored.end, model.duration)

        let reopened = VideoTrimModel(wallpaper: Wallpaper(url: fixture.video), store: fixture.store, isInLibrary: { _ in true })
        defer { reopened.stopPreview() }
        await reopened.load()
        XCTAssertEqual(reopened.start, stored.start)
        XCTAssertEqual(reopened.end, reopened.duration, "End reopens exactly at the end of the video")
        reopened.stepStart(frames: 1)
        XCTAssertTrue(reopened.save(), reopened.error ?? "")
        reopened.resetToFullVideo()
        XCTAssertTrue(reopened.isFullVideo)
        XCTAssertTrue(reopened.save(), reopened.error ?? "")
        XCTAssertNil(fixture.store.trim(for: fixture.video), "A full selection removes the trim")
    }

    func testPreviewRangeStaysInsideTheItem() {
        let trackEnd = CMTime(value: 3_066_667, timescale: 1_000_000)
        let itemDuration = CMTime(value: 3_066, timescale: 1_000)
        XCTAssertEqual(VideoTrimModel.previewRange(start: CMTime(value: 1, timescale: 1), end: trackEnd,
                                                   itemDuration: itemDuration)?.end, itemDuration)
        XCTAssertEqual(VideoTrimModel.previewRange(start: .zero, end: CMTime(value: 2, timescale: 1),
                                                   itemDuration: itemDuration)?.end, CMTime(value: 2, timescale: 1))
        XCTAssertNil(VideoTrimModel.previewRange(start: itemDuration, end: trackEnd, itemDuration: itemDuration))
        XCTAssertNil(VideoTrimModel.previewRange(start: .zero, end: trackEnd, itemDuration: .invalid))
        let nanoStart = CMTime(value: 333_333_330, timescale: 1_000_000_000)
        let sixHundredths = CMTime(value: 2_419, timescale: 600)
        let mixed = try? XCTUnwrap(VideoTrimModel.previewRange(start: nanoStart, end: sixHundredths,
                                                               itemDuration: sixHundredths))
        XCTAssertLessThanOrEqual(mixed?.end ?? .positiveInfinity, sixHundredths,
                                 "A rounded duration must not end past the item")
    }

    func testTimeTextForDisplayAndVoiceOver() {
        XCTAssertEqual(VideoTrimModel.clockText(CMTime(value: 624, timescale: 10)), "1:02.40")
        XCTAssertEqual(VideoTrimModel.clockText(.zero), "0:00.00")
        XCTAssertEqual(VideoTrimModel.spokenText(CMTime(value: 624, timescale: 10)), "1 minute 2.40 seconds")
        XCTAssertEqual(VideoTrimModel.spokenText(CMTime(value: 125, timescale: 1)), "2 minutes 5.00 seconds")
        XCTAssertEqual(VideoTrimModel.spokenText(CMTime(value: 5, timescale: 1)), "5.00 seconds")
        // Frame 8991 at 29.97 fps, 299.9997 s, carries into the minute.
        XCTAssertEqual(VideoTrimModel.clockText(CMTime(value: 8_999_991, timescale: 30_000)), "5:00.00")
        XCTAssertEqual(VideoTrimModel.spokenText(CMTime(value: 8_999_991, timescale: 30_000)), "5 minutes 0.00 seconds")
        XCTAssertEqual(VideoTrimModel.clockText(CMTime(value: 71_998, timescale: 600)), "2:00.00")
        XCTAssertEqual(VideoTrimModel.clockText(CMTime(value: 35_999, timescale: 600)), "1:00.00")
    }
}

/// A short 10 fps video in its own directory, with an isolated range store.
@MainActor
private struct Fixture {
    let directory: URL
    let video: URL
    let suite: String
    let store: PlaybackTrimStore

    init(frames: Int) async throws {
        try await self.init(times: (0..<frames).map { CMTime(value: Int64($0), timescale: 10) },
                            end: CMTime(value: Int64(frames), timescale: 10))
    }

    /// Frames at `times`, ending at `end`. A first frame after zero leaves an
    /// empty edit before it, as with a video that starts after its audio.
    init(times: [CMTime], end: CMTime, mediaTimeScale: CMTimeScale? = nil) async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("trim-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        video = directory.appendingPathComponent("loop.mov")
        suite = "VideoTrimModel.\(UUID().uuidString)"
        store = PlaybackTrimStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        try await Self.writeVideo(to: video, times: times, end: end, mediaTimeScale: mediaTimeScale)
    }

    func remove() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    static func writeVideo(to url: URL, frames: Int) async throws {
        try await writeVideo(to: url, times: (0..<frames).map { CMTime(value: Int64($0), timescale: 10) },
                             end: CMTime(value: Int64(frames), timescale: 10))
    }

    static func writeVideo(to url: URL, times: [CMTime], end: CMTime,
                           mediaTimeScale: CMTimeScale? = nil) async throws {
        try? FileManager.default.removeItem(at: url)
        let size = 32
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size, AVVideoHeightKey: size
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size, kCVPixelBufferHeightKey as String: size
        ])
        if let mediaTimeScale { input.mediaTimeScale = mediaTimeScale }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, size, size, kCVPixelFormatType_32BGRA, nil, &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer else { throw CocoaError(.fileWriteUnknown) }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) { memset(base, 90, CVPixelBufferGetBytesPerRow(buffer) * size) }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        for time in times {
            let deadline = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing, Date() < deadline else {
                    writer.cancelWriting()
                    throw writer.error ?? CocoaError(.fileWriteUnknown)
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard adaptor.append(buffer, withPresentationTime: time) else {
                writer.cancelWriting()
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
        }
        writer.endSession(atSourceTime: end)
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
}
