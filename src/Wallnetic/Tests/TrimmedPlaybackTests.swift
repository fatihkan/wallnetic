import XCTest
import AVFoundation
import CoreMedia
@testable import Wallnetic

/// #309: trimmed playback in both engines. The fixture's frames are flat gray
/// levels that identify each frame, so decoded output shows which frames play.
final class TrimmedPlaybackTests: XCTestCase {
    private let fps: Int32 = 10
    private let frameCount = 30 // 3 s

    private func level(ofFrame index: Int) -> Int { 16 + index * 7 }

    @MainActor
    func testTrimmedAssetStartsAtTheStartFrameAndEndsBeforeEnd() async throws {
        let video = temporaryVideoURL("composition")
        defer { try? FileManager.default.removeItem(at: video) }
        let rotation = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 64, ty: 0)
        try await writeNumberedVideo(to: video, transform: rotation)
        let trim = try trimming(video, fromFrame: 10, toFrame: 20)

        let source = TrimmedVideoAsset.sourceAsset(url: video, trim: trim)
        let playback = await TrimmedVideoAsset.playbackAsset(for: source, trim: trim)
        XCTAssertEqual(playback.trim, trim)
        let composition = try XCTUnwrap(playback.asset as? AVComposition)
        let duration = try await composition.load(.duration)
        XCTAssertEqual(duration.seconds, 1, accuracy: 0.001, "The item's timeline starts at zero and spans the range")
        let tracks = try await composition.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let transform = try await track.load(.preferredTransform)
        XCTAssertEqual(transform, rotation, "Without the source transform, rotated videos play sideways")

        let frames = try await decodedFrames(of: composition)
        XCTAssertEqual(frames.count, 10)
        XCTAssertEqual(frames.first?.time.seconds ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(Double(frames.first?.level ?? -1), Double(level(ofFrame: 10)), accuracy: 3,
                       "The first frame is the Start frame")
        XCTAssertEqual(Double(frames.last?.level ?? -1), Double(level(ofFrame: 19)), accuracy: 3,
                       "The last frame is the one before End")
    }

    @MainActor
    func testARangeThatDoesNotFitPlaysTheSourceInFull() async throws {
        let video = temporaryVideoURL("outside")
        defer { try? FileManager.default.removeItem(at: video) }
        try await writeNumberedVideo(to: video)
        let fingerprint = try XCTUnwrap(VideoFileFingerprint(fileAt: video))
        let outside = PlaybackTrim(start: CMTime(value: 25, timescale: 10), end: CMTime(value: 35, timescale: 10),
                                   fingerprint: fingerprint)
        let source = TrimmedVideoAsset.sourceAsset(url: video, trim: outside)
        let playback = await TrimmedVideoAsset.playbackAsset(for: source, trim: outside)
        XCTAssertNil(playback.trim)
        XCTAssertTrue(playback.asset === source)
        let untrimmed = await TrimmedVideoAsset.playbackAsset(for: source, trim: nil)
        XCTAssertTrue(untrimmed.asset === source)
    }

    @MainActor
    func testAVFoundationLoopsOnlyTheRange() async throws {
        let renderer = VideoRenderer()
        try await assertLoopsOnlyTheRange(renderer, applied: { renderer.appliedTrim })
    }

    @MainActor
    func testMetalLoopsOnlyTheRange() async throws {
        guard MetalVideoRenderer.isSupported else { throw XCTSkip("Metal is unavailable") }
        let renderer = MetalVideoRenderer()
        try await assertLoopsOnlyTheRange(renderer, applied: { renderer.appliedTrim })
    }

    @MainActor
    func testAVFoundationPlaysTheFullVideoForAReplacedFile() async throws {
        let renderer = VideoRenderer()
        try await assertReplacedFilePlaysInFull(renderer, applied: { renderer.appliedTrim })
    }

    @MainActor
    func testMetalPlaysTheFullVideoForAReplacedFile() async throws {
        guard MetalVideoRenderer.isSupported else { throw XCTSkip("Metal is unavailable") }
        let renderer = MetalVideoRenderer()
        try await assertReplacedFilePlaysInFull(renderer, applied: { renderer.appliedTrim })
    }

    @MainActor
    func testAVFoundationTrimEditsKeepEveryPauseOwner() async throws {
        let renderer = VideoRenderer()
        try await assertTrimEditsKeepPauseOwnership(renderer, applied: { renderer.appliedTrim })
    }

    @MainActor
    func testMetalTrimEditsKeepEveryPauseOwner() async throws {
        guard MetalVideoRenderer.isSupported else { throw XCTSkip("Metal is unavailable") }
        let renderer = MetalVideoRenderer()
        try await assertTrimEditsKeepPauseOwnership(renderer, applied: { renderer.appliedTrim })
    }

    @MainActor
    func testAVFoundationTrimReloadNeverRestartsThePreviousRange() async throws {
        let renderer = VideoRenderer()
        try await assertTrimReloadIsExclusive(renderer, applied: { renderer.appliedTrim })
    }

    @MainActor
    func testMetalTrimReloadNeverRestartsThePreviousRange() async throws {
        guard MetalVideoRenderer.isSupported else { throw XCTSkip("Metal is unavailable") }
        let renderer = MetalVideoRenderer()
        try await assertTrimReloadIsExclusive(renderer, applied: { renderer.appliedTrim })
    }

    @MainActor
    func testAVFoundationRemovingARangeThatDoesNotApplyKeepsPlaying() async throws {
        let renderer = VideoRenderer()
        try await assertUnappliedRangeRemovalKeepsPlayer(renderer, applied: { renderer.appliedTrim })
    }

    @MainActor
    func testMetalRemovingARangeThatDoesNotApplyKeepsPlaying() async throws {
        guard MetalVideoRenderer.isSupported else { throw XCTSkip("Metal is unavailable") }
        let renderer = MetalVideoRenderer()
        try await assertUnappliedRangeRemovalKeepsPlayer(renderer, applied: { renderer.appliedTrim })
    }

    @MainActor
    func testAVFoundationReportsWhetherTheRangeApplied() async throws {
        try await assertReportsTrimOutcome(VideoRenderer())
    }

    @MainActor
    func testMetalReportsWhetherTheRangeApplied() async throws {
        guard MetalVideoRenderer.isSupported else { throw XCTSkip("Metal is unavailable") }
        try await assertReportsTrimOutcome(MetalVideoRenderer())
    }

    // MARK: - Scenarios

    /// While a trim edit loads, no resume path may restart the previous range,
    /// and a pause that arrives during the load ends Paused on the edited
    /// range's first frame, never Loading.
    @MainActor
    private func assertTrimReloadIsExclusive(_ renderer: WallpaperRenderer,
                                             applied: @escaping () -> PlaybackTrim?) async throws {
        let video = temporaryVideoURL("exclusive")
        let window = host(renderer)
        defer { cleanUp(renderer, window: window, video: video) }
        try await writeNumberedVideo(to: video)
        let first = try trimming(video, fromFrame: 10, toFrame: 20)
        let second = try trimming(video, fromFrame: 5, toFrame: 25)
        renderer.loadVideo(url: video, trim: nil)
        renderer.play()
        try await waitUntil("first frame") { renderer.playbackMonitor.hasFrameForCurrentLoad }

        // A pause right after an edit made while playing.
        renderer.applyTrim(first)
        renderer.pause()
        try await waitUntil("edited frame while paused") {
            applied() == first && renderer.playbackMonitor.hasFrameForCurrentLoad
                && renderer.playbackMonitor.state == .paused
        }
        XCTAssertEqual(renderer.currentPlaybackRate, 0)
        XCTAssertLessThanOrEqual(renderer.currentPlaybackTime ?? 99, 1.05)

        // Resume calls that race the deferred reload cannot restart the old player.
        renderer.applyTrim(second)
        renderer.play()
        renderer.maintainPlayback()
        renderer.recoverPlayback()
        renderer.play()
        XCTAssertEqual(renderer.currentPlaybackRate, 0, "The previous range's player stays paused")
        try await waitUntil("edited range after resume") {
            applied() == second && renderer.playbackMonitor.hasFrameForCurrentLoad && renderer.currentPlaybackRate == 1
        }

        // Play then Pause within the deferred reload's load.
        renderer.pause()
        renderer.applyTrim(first)
        renderer.play()
        renderer.pause()
        try await waitUntil("edited frame after a quick toggle") {
            applied() == first && renderer.playbackMonitor.hasFrameForCurrentLoad
                && renderer.playbackMonitor.state == .paused
        }
        XCTAssertEqual(renderer.currentPlaybackRate, 0)
    }

    /// The full video plays for a range that does not apply. Removing that
    /// range changes nothing that plays, so neither a playing nor a paused
    /// display restarts from the beginning.
    @MainActor
    private func assertUnappliedRangeRemovalKeepsPlayer(_ renderer: WallpaperRenderer,
                                                        applied: @escaping () -> PlaybackTrim?) async throws {
        let video = temporaryVideoURL("unapplied")
        let window = host(renderer)
        defer { cleanUp(renderer, window: window, video: video) }
        try await writeNumberedVideo(to: video)
        let stale = PlaybackTrim(start: CMTime(value: 1, timescale: 1), end: CMTime(value: 2, timescale: 1),
                                 fingerprint: VideoFileFingerprint(byteSize: 1, modificationDate: .distantPast))
        renderer.loadVideo(url: video, trim: stale)
        renderer.play()
        try await waitUntil("first frame") { renderer.playbackMonitor.hasFrameForCurrentLoad }
        try await waitUntil("playback underway") { (renderer.currentPlaybackTime ?? 0) > 0.4 }
        XCTAssertNil(applied())

        let playing = try XCTUnwrap(renderer.currentPlaybackTime)
        renderer.applyTrim(nil)
        XCTAssertTrue(renderer.playbackMonitor.hasFrameForCurrentLoad, "Removing it does not reload")
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertGreaterThan(renderer.currentPlaybackTime ?? 0, playing, "Playback continues instead of restarting")

        renderer.applyTrim(stale)
        XCTAssertTrue(renderer.playbackMonitor.hasFrameForCurrentLoad)
        renderer.pause()
        try await waitUntil("paused") { renderer.playbackMonitor.state == .paused }
        let paused = try XCTUnwrap(renderer.currentPlaybackTime)
        renderer.applyTrim(nil)
        renderer.play()
        XCTAssertTrue(renderer.playbackMonitor.hasFrameForCurrentLoad, "Nothing was deferred for the resume")
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertGreaterThan(renderer.currentPlaybackTime ?? 0, paused, "The resume continues where it paused")
    }

    @MainActor
    private func assertLoopsOnlyTheRange(_ renderer: WallpaperRenderer,
                                         applied: @escaping () -> PlaybackTrim?) async throws {
        let video = temporaryVideoURL("loop")
        let window = host(renderer)
        defer { cleanUp(renderer, window: window, video: video) }
        try await writeNumberedVideo(to: video)
        let trim = try trimming(video, fromFrame: 10, toFrame: 20)
        renderer.loadVideo(url: video, trim: trim)
        renderer.play()
        try await waitUntil("first frame") { renderer.playbackMonitor.hasFrameForCurrentLoad }
        XCTAssertEqual(applied(), trim)

        var last = renderer.currentPlaybackTime ?? 0
        var latest = last
        var wraps = 0
        let deadline = Date().addingTimeInterval(6)
        while wraps < 2, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
            guard let time = renderer.currentPlaybackTime else { continue }
            latest = max(latest, time)
            if last - time > 0.3 { wraps += 1 }
            last = time
        }
        XCTAssertGreaterThanOrEqual(wraps, 2)
        XCTAssertLessThanOrEqual(latest, 1.05, "The playback clock stays within the trimmed length")
    }

    @MainActor
    private func assertReplacedFilePlaysInFull(_ renderer: WallpaperRenderer,
                                               applied: @escaping () -> PlaybackTrim?) async throws {
        let video = temporaryVideoURL("replaced")
        let window = host(renderer)
        defer { cleanUp(renderer, window: window, video: video) }
        try await writeNumberedVideo(to: video)
        let stale = PlaybackTrim(start: CMTime(value: 1, timescale: 1), end: CMTime(value: 2, timescale: 1),
                                 fingerprint: VideoFileFingerprint(byteSize: 1, modificationDate: .distantPast))
        renderer.loadVideo(url: video, trim: stale)
        renderer.play()
        try await waitUntil("first frame") { renderer.playbackMonitor.hasFrameForCurrentLoad }
        XCTAssertNil(applied())
        try await waitUntil("playback past the stale range") { (renderer.currentPlaybackTime ?? 0) > 1.2 }
        XCTAssertFalse(renderer.playbackMonitor.state.isFailed, "The full video plays instead of a failed wallpaper")
    }

    @MainActor
    private func assertTrimEditsKeepPauseOwnership(_ renderer: WallpaperRenderer,
                                                   applied: @escaping () -> PlaybackTrim?) async throws {
        let video = temporaryVideoURL("ownership")
        let window = host(renderer)
        defer { cleanUp(renderer, window: window, video: video) }
        try await writeNumberedVideo(to: video)
        let first = try trimming(video, fromFrame: 10, toFrame: 20)
        let second = try trimming(video, fromFrame: 5, toFrame: 25)
        var clock = 0.0
        var allowed = true
        let playback = PauseAfterPlayback(now: { clock }, canPlay: { allowed })
        renderer.loadVideo(url: video, trim: nil)
        playback.setWallpaper(video, renderer: renderer, on: 1, preferences: .init(defaultSeconds: 15))
        playback.play()
        try await waitUntil("first frame") { renderer.playbackMonitor.hasFrameForCurrentLoad }
        playback.tick()
        renderer.applyTrim(nil)
        XCTAssertTrue(renderer.playbackMonitor.hasFrameForCurrentLoad, "An unchanged range does not reload")

        // A running interval: the edit reloads at once and keeps the deadline.
        clock = 5
        renderer.applyTrim(first)
        try await waitUntil("edited range while playing") {
            renderer.playbackMonitor.hasFrameForCurrentLoad && applied() == first
        }
        XCTAssertEqual(renderer.currentPlaybackRate, 1)
        XCTAssertLessThanOrEqual(renderer.currentPlaybackTime ?? 99, 1.05)
        clock = 14.999
        playback.tick()
        XCTAssertFalse(playback.isExpired(on: 1))
        clock = 15
        playback.tick()
        XCTAssertTrue(playback.isExpired(on: 1), "The edit neither restarts nor extends the interval")

        // After expiry: the edit waits for Play and never resumes the display.
        try await assertEditWaits(renderer, applied: applied, edit: second, keeping: first)
        XCTAssertTrue(playback.isExpired(on: 1))
        playback.play(explicit: true)
        try await waitUntil("edited range after Play") {
            renderer.playbackMonitor.hasFrameForCurrentLoad && applied() == second
        }
        XCTAssertEqual(renderer.currentPlaybackRate, 1)

        // A manual pause: an automatic resume still cannot start it.
        playback.pause(manual: true)
        try await assertEditWaits(renderer, applied: applied, edit: first, keeping: second)
        playback.play()
        XCTAssertEqual(renderer.currentPlaybackRate, 0)
        XCTAssertEqual(applied(), second)
        playback.play(explicit: true)
        try await waitUntil("edited range after manual Play") {
            renderer.playbackMonitor.hasFrameForCurrentLoad && applied() == first
        }

        // A power pause whose automatic resume is disabled: the condition
        // clears, nothing resumes, and the display never reads Loading.
        allowed = false
        playback.pause(manual: false)
        try await assertEditWaits(renderer, applied: applied, edit: nil, keeping: first)
        allowed = true
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(renderer.currentPlaybackRate, 0)
        XCTAssertEqual(renderer.playbackMonitor.state, .paused)
        playback.play()
        try await waitUntil("full video after the power resume") {
            renderer.playbackMonitor.hasFrameForCurrentLoad && applied() == nil && renderer.currentPlaybackRate == 1
        }

        // A Calm Mode hold.
        playback.setHolds([.calm])
        try await assertEditWaits(renderer, applied: applied, edit: second, keeping: nil)
        playback.setHolds([])
        try await waitUntil("edited range after the hold") {
            renderer.playbackMonitor.hasFrameForCurrentLoad && applied() == second
        }
        XCTAssertEqual(renderer.currentPlaybackRate, 1)
    }

    /// A paused renderer keeps its frame, position and Paused status after an
    /// edit, and keeps playing the previous range until it resumes.
    @MainActor
    private func assertEditWaits(_ renderer: WallpaperRenderer, applied: () -> PlaybackTrim?,
                                 edit: PlaybackTrim?, keeping current: PlaybackTrim?,
                                 file: StaticString = #filePath, line: UInt = #line) async throws {
        try await waitUntil("paused status", file: file, line: line) { renderer.playbackMonitor.state == .paused }
        let time = renderer.currentPlaybackTime
        renderer.applyTrim(edit)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(renderer.currentPlaybackRate, 0, file: file, line: line)
        XCTAssertEqual(renderer.playbackMonitor.state, .paused, "A paused display never reads Loading", file: file, line: line)
        XCTAssertTrue(renderer.hasPresentedFrame, file: file, line: line)
        XCTAssertEqual(renderer.currentPlaybackTime ?? -1, time ?? -2, accuracy: 0.02, file: file, line: line)
        XCTAssertEqual(applied(), current, "The edit applies on the next resume", file: file, line: line)
    }

    /// The Library shows a range as not applied when the renderer had to play
    /// the full video instead, including a range it could not build.
    @MainActor
    private func assertReportsTrimOutcome(_ renderer: WallpaperRenderer) async throws {
        let video = temporaryVideoURL("outcome")
        let window = host(renderer)
        defer { cleanUp(renderer, window: window, video: video) }
        try await writeNumberedVideo(to: video)
        renderer.loadVideo(url: video, trim: nil)
        renderer.play()
        try await waitUntil("first frame") { renderer.playbackMonitor.hasFrameForCurrentLoad }
        XCTAssertNil(renderer.trimOutcome, "No range, nothing to report")

        renderer.loadVideo(url: video, trim: try trimming(video, fromFrame: 10, toFrame: 20))
        try await waitUntil("trimmed frame") { renderer.playbackMonitor.hasFrameForCurrentLoad }
        XCTAssertEqual(renderer.trimOutcome?.applied, true)
        XCTAssertEqual(renderer.trimOutcome?.url, video)

        let fingerprint = try XCTUnwrap(VideoFileFingerprint(fileAt: video))
        let outside = PlaybackTrim(start: CMTime(value: 25, timescale: 10), end: CMTime(value: 35, timescale: 10),
                                   fingerprint: fingerprint)
        renderer.loadVideo(url: video, trim: outside)
        try await waitUntil("full-video frame") { renderer.playbackMonitor.hasFrameForCurrentLoad }
        XCTAssertEqual(renderer.trimOutcome?.applied, false, "The full video plays, and the Library is told")

        renderer.pause()
        try await waitUntil("paused") { renderer.playbackMonitor.state == .paused }
        renderer.applyTrim(try trimming(video, fromFrame: 10, toFrame: 20))
        XCTAssertNil(renderer.trimOutcome, "A deferred edit reports nothing until it loads")
        renderer.play()
        try await waitUntil("edited range applied") { renderer.trimOutcome?.applied == true }
    }

    // MARK: - Fixtures

    private func trimming(_ video: URL, fromFrame start: Int, toFrame end: Int) throws -> PlaybackTrim {
        let fingerprint = try XCTUnwrap(VideoFileFingerprint(fileAt: video))
        return try XCTUnwrap(PlaybackTrim.selection(
            start: CMTime(value: Int64(start), timescale: fps), end: CMTime(value: Int64(end), timescale: fps),
            duration: CMTime(value: Int64(frameCount), timescale: fps), fingerprint: fingerprint))
    }

    private func temporaryVideoURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("trim-\(name)-\(UUID().uuidString).mov")
    }

    @MainActor
    private func host(_ renderer: WallpaperRenderer) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 96, height: 96), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = renderer.rendererView
        window.orderFront(nil)
        return window
    }

    @MainActor
    private func cleanUp(_ renderer: WallpaperRenderer, window: NSWindow, video: URL) {
        renderer.stop()
        window.contentView = nil
        window.close()
        try? FileManager.default.removeItem(at: video)
    }

    @MainActor
    private func waitUntil(_ what: String, timeout: TimeInterval = 5, file: StaticString = #filePath,
                           line: UInt = #line, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition(), "Timed out waiting for \(what)", file: file, line: line)
    }

    /// Presentation times and gray levels of every decoded frame, in display order.
    private func decodedFrames(of asset: AVAsset) async throws -> [(time: CMTime, level: Int)] {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var frames: [(time: CMTime, level: Int)] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let image = CMSampleBufferGetImageBuffer(sample) else { continue }
            CVPixelBufferLockBaseAddress(image, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(image) else { continue }
            let row = CVPixelBufferGetBytesPerRow(image)
            let center = (CVPixelBufferGetHeight(image) / 2) * row + (CVPixelBufferGetWidth(image) / 2) * 4
            frames.append((CMSampleBufferGetPresentationTimeStamp(sample),
                           Int(base.load(fromByteOffset: center + 1, as: UInt8.self))))
        }
        XCTAssertEqual(reader.status, .completed)
        return frames.sorted { $0.time < $1.time }
    }

    private func writeNumberedVideo(to url: URL, transform: CGAffineTransform = .identity) async throws {
        let size = 64
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size,
            AVVideoHeightKey: size
        ])
        input.transform = transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size,
            kCVPixelBufferHeightKey as String: size
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? FixtureError.encodingFailed }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<frameCount {
            var pixelBuffer: CVPixelBuffer?
            guard CVPixelBufferCreate(kCFAllocatorDefault, size, size, kCVPixelFormatType_32BGRA, nil, &pixelBuffer) == kCVReturnSuccess,
                  let buffer = pixelBuffer else { throw FixtureError.encodingFailed }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, Int32(level(ofFrame: frame)), CVPixelBufferGetBytesPerRow(buffer) * size)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            let deadline = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing, Date() < deadline else {
                    writer.cancelWriting()
                    throw writer.error ?? FixtureError.encodingFailed
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: fps)) else {
                writer.cancelWriting()
                throw writer.error ?? FixtureError.encodingFailed
            }
        }
        writer.endSession(atSourceTime: CMTime(value: Int64(frameCount), timescale: fps))
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? FixtureError.encodingFailed }
    }

    private enum FixtureError: Error { case encodingFailed }
}
