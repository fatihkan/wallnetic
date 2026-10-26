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

    func testTimeTextForDisplayAndVoiceOver() {
        XCTAssertEqual(VideoTrimModel.clockText(CMTime(value: 624, timescale: 10)), "1:02.40")
        XCTAssertEqual(VideoTrimModel.clockText(.zero), "0:00.00")
        XCTAssertEqual(VideoTrimModel.spokenText(CMTime(value: 624, timescale: 10)), "1 minute 2.40 seconds")
        XCTAssertEqual(VideoTrimModel.spokenText(CMTime(value: 125, timescale: 1)), "2 minutes 5.00 seconds")
        XCTAssertEqual(VideoTrimModel.spokenText(CMTime(value: 5, timescale: 1)), "5.00 seconds")
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
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("trim-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        video = directory.appendingPathComponent("loop.mov")
        suite = "VideoTrimModel.\(UUID().uuidString)"
        store = PlaybackTrimStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        try await Self.writeVideo(to: video, frames: frames)
    }

    func remove() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    static func writeVideo(to url: URL, frames: Int) async throws {
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
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, size, size, kCVPixelFormatType_32BGRA, nil, &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer else { throw CocoaError(.fileWriteUnknown) }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) { memset(base, 90, CVPixelBufferGetBytesPerRow(buffer) * size) }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        for frame in 0..<frames {
            let deadline = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing, Date() < deadline else {
                    writer.cancelWriting()
                    throw writer.error ?? CocoaError(.fileWriteUnknown)
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 10)) else {
                writer.cancelWriting()
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
        }
        writer.endSession(atSourceTime: CMTime(value: Int64(frames), timescale: 10))
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
}
