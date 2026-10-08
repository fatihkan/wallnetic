import XCTest
import AVFoundation
import AppKit
import Combine
@testable import Wallnetic

final class PlaybackRendererTests: XCTestCase {
    @MainActor
    func testMetalPresentsFramesAndCanStopAfterSubmittingDraws() async throws {
        guard MetalVideoRenderer.isSupported else { throw XCTSkip("Metal is unavailable") }
        let renderer = MetalVideoRenderer()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 96, height: 96), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let video = FileManager.default.temporaryDirectory.appendingPathComponent("gpu-\(UUID().uuidString).mov")
        defer {
            renderer.stop()
            window.contentView = nil
            window.close()
            try? FileManager.default.removeItem(at: video)
        }
        try await writeShortVideo(to: video)
        window.contentView = renderer.metalView
        window.orderFront(nil)
        renderer.loadVideo(url: video)
        renderer.play()
        let deadline = Date().addingTimeInterval(5)
        while !renderer.hasPresentedFrame, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(renderer.hasPresentedFrame)
        for _ in 0..<10 { renderer.metalView.draw() }
        renderer.stop()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(renderer.hasPresentedFrame)
        XCTAssertNil(renderer.currentPlaybackTime)
    }

    @MainActor
    func testConcurrentFrameRequestsCoalesceOnMain() async {
        var frames = 0
        let scheduler = DisplayLinkFrameScheduler {
            XCTAssertTrue(Thread.isMainThread)
            frames += 1
        }
        DispatchQueue.concurrentPerform(iterations: 500) { _ in scheduler.requestFrame(at: 0) }
        await drainMainQueue()
        XCTAssertEqual(frames, 1)
        scheduler.requestFrame(at: 1.0 / 60)
        await drainMainQueue()
        XCTAssertEqual(frames, 2)
        scheduler.invalidate()
    }

    @MainActor
    func testInvalidatedSessionCannotDrawAfterRestart() async {
        var oldFrames = 0
        var newFrames = 0
        let old = DisplayLinkFrameScheduler { oldFrames += 1 }
        old.requestFrame()
        old.invalidate()
        let replacement = DisplayLinkFrameScheduler { newFrames += 1 }
        DispatchQueue.concurrentPerform(iterations: 500) { _ in
            old.requestFrame()
            replacement.requestFrame()
        }
        await drainMainQueue()
        XCTAssertEqual(oldFrames, 0)
        XCTAssertEqual(newFrames, 1)
        replacement.invalidate()
    }

    @MainActor
    func testAVFoundationKeepsLoopingAfterFailedReplacement() async throws {
        try await assertKeepsLoopingAfterFailedReplacement(VideoRenderer())
    }

    @MainActor
    func testMetalKeepsLoopingAfterFailedReplacement() async throws {
        guard MetalVideoRenderer.isSupported else { throw XCTSkip("Metal is unavailable") }
        try await assertKeepsLoopingAfterFailedReplacement(MetalVideoRenderer())
    }

    @MainActor
    func testAVFoundationStopInvalidatesPendingLoad() async throws {
        try await assertStopInvalidatesPendingLoad(VideoRenderer())
    }

    @MainActor
    func testMetalStopInvalidatesPendingLoad() async throws {
        guard MetalVideoRenderer.isSupported else { throw XCTSkip("Metal is unavailable") }
        try await assertStopInvalidatesPendingLoad(MetalVideoRenderer())
    }

    @MainActor
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @MainActor
    private func assertKeepsLoopingAfterFailedReplacement(_ renderer: WallpaperRenderer) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            renderer.stop()
            try? FileManager.default.removeItem(at: directory)
        }
        let video = directory.appendingPathComponent("loop.mov")
        let invalid = directory.appendingPathComponent("invalid.mov")
        try Data("not a video".utf8).write(to: invalid)
        try await writeShortVideo(to: video)
        renderer.loadVideo(url: video)
        renderer.play()
        let readyDeadline = Date().addingTimeInterval(5)
        while (renderer.currentPlaybackTime ?? 0) < 0.03, Date() < readyDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertGreaterThan(renderer.currentPlaybackTime ?? 0, 0.02, "Initial video must start")

        renderer.loadVideo(url: invalid)
        var lastTime = renderer.currentPlaybackTime ?? 0
        var wraps = 0
        let deadline = Date().addingTimeInterval(3)
        while wraps < 2, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
            if let time = renderer.currentPlaybackTime {
                if lastTime - time > 0.05 { wraps += 1 }
                lastTime = time
            }
        }
        XCTAssertGreaterThanOrEqual(wraps, 2, "A failed replacement must not disable the active player's loop")
        XCTAssertTrue(renderer.playbackMonitor.state.isFailed, "The previous video must not mask the failed selection")
        renderer.pause()
        try await Task.sleep(nanoseconds: 100_000_000)
        let pausedTime = renderer.currentPlaybackTime
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(renderer.currentPlaybackRate, 0)
        XCTAssertEqual(renderer.currentPlaybackTime ?? -1, pausedTime ?? -1, accuracy: 0.02)
    }

    @MainActor
    private func assertStopInvalidatesPendingLoad(_ renderer: WallpaperRenderer) async throws {
        let video = FileManager.default.temporaryDirectory.appendingPathComponent("stop-\(UUID().uuidString).mov")
        defer {
            renderer.stop()
            try? FileManager.default.removeItem(at: video)
        }
        try await writeShortVideo(to: video)
        renderer.loadVideo(url: video)
        renderer.play()
        // Stop before the asynchronous asset load can attach its player.
        renderer.stop()
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertNil(renderer.currentPlaybackTime)
        XCTAssertEqual(renderer.currentPlaybackRate, 0)
        XCTAssertFalse(renderer.hasPresentedFrame)
    }

    private func writeShortVideo(to url: URL, frames: Int = 3, fps: Int32 = 10) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64,
            kCVPixelBufferHeightKey as String: 64
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? FixtureError.encodingFailed }
        writer.startSession(atSourceTime: .zero)
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer else { throw FixtureError.encodingFailed }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, 128, CVPixelBufferGetBytesPerRow(buffer) * 64)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        for frame in 0..<frames {
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
        writer.endSession(atSourceTime: CMTime(value: Int64(frames), timescale: fps))
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? FixtureError.encodingFailed }
    }

    @MainActor
    func testDurationPauseHoldsAVPlayerFrameUntilExplicitResume() async throws {
        try await assertDurationPause(VideoRenderer())
    }

    @MainActor
    func testDurationPauseHoldsMetalFrameUntilExplicitResume() async throws {
        guard MetalVideoRenderer.isSupported else { throw XCTSkip("Metal is unavailable") }
        try await assertDurationPause(MetalVideoRenderer())
    }

    @MainActor
    private func assertDurationPause(_ renderer: WallpaperRenderer) async throws {
        let video = FileManager.default.temporaryDirectory.appendingPathComponent("duration-\(UUID().uuidString).mov")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 96, height: 96), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            renderer.stop()
            window.contentView = nil
            window.close()
            try? FileManager.default.removeItem(at: video)
        }
        try await writeShortVideo(to: video)
        window.contentView = renderer.rendererView
        window.orderFront(nil)
        var time = 0.0
        let playback = PauseAfterPlayback(now: { time }, canPlay: { true })
        renderer.loadVideo(url: video)
        playback.setWallpaper(video, renderer: renderer, on: 1, preferences: .init(defaultSeconds: 15))
        playback.play()
        let deadline = Date().addingTimeInterval(5)
        while !renderer.hasPresentedFrame, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(renderer.hasPresentedFrame)
        playback.tick()
        time = 15
        playback.tick()
        renderer.maintainPlayback() // App activation must not revive motion.
        try await Task.sleep(nanoseconds: 100_000_000)
        let frozenTime = renderer.currentPlaybackTime
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(renderer.currentPlaybackRate, 0)
        XCTAssertEqual(renderer.currentPlaybackTime ?? -1, frozenTime ?? -1, accuracy: 0.02)
        XCTAssertTrue(renderer.hasPresentedFrame)
        XCTAssertTrue(playback.isPausedAfterDuration)
        if let layer = renderer.filterLayer as? AVPlayerLayer {
            XCTAssertNotNil(layer.displayedPixelBuffer())
        }
        playback.play(explicit: true)
        XCTAssertEqual(renderer.currentPlaybackRate, 1)
        XCTAssertFalse(playback.isPausedAfterDuration)
    }

    @MainActor
    func testAVFoundationReportsLoadFailureRetryAndManualPause() async throws {
        try await assertStatusLifecycle(VideoRenderer())
    }

    @MainActor
    func testMetalReportsLoadFailureRetryAndManualPause() async throws {
        guard MetalVideoRenderer.isSupported else { throw XCTSkip("Metal is unavailable") }
        try await assertStatusLifecycle(MetalVideoRenderer())
    }

    @MainActor
    private func assertStatusLifecycle(_ renderer: WallpaperRenderer) async throws {
        let video = FileManager.default.temporaryDirectory.appendingPathComponent("status-\(UUID().uuidString).mov")
        let missing = video.appendingPathExtension("missing")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 96, height: 96), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            renderer.stop()
            window.contentView = nil
            window.close()
            try? FileManager.default.removeItem(at: video)
        }
        try await writeShortVideo(to: video, frames: 30)
        window.contentView = renderer.rendererView
        window.orderFront(nil)
        renderer.loadVideo(url: video)
        XCTAssertEqual(renderer.playbackMonitor.state, .loading)
        // A later missing selection invalidates even a pending valid load.
        renderer.loadVideo(url: missing)
        XCTAssertEqual(renderer.playbackMonitor.state, .failed(.missingFile))
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(renderer.playbackMonitor.state, .failed(.missingFile))
        XCTAssertNil(renderer.currentPlaybackTime)

        var allowed = true
        let playback = PauseAfterPlayback(canPlay: { allowed })
        playback.setWallpaper(video, renderer: renderer, on: 1, preferences: .init())
        playback.pause(manual: true)
        renderer.loadVideo(url: video)
        playback.setWallpaper(video, renderer: renderer, on: 1, preferences: .init())
        playback.play() // The retry path must not revoke manual Pause.
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(renderer.currentPlaybackRate, 0)
        XCTAssertNotEqual(renderer.playbackMonitor.state, .playing)
        allowed = false
        playback.play(explicit: true)
        XCTAssertEqual(renderer.currentPlaybackRate, 0)
        allowed = true
        playback.play(explicit: true)
        let deadline = Date().addingTimeInterval(5)
        while renderer.playbackMonitor.state != .playing, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(renderer.playbackMonitor.state, .playing)
        XCTAssertTrue(renderer.hasPresentedFrame)
        playback.pause(manual: true)
        await drainMainQueue()
        XCTAssertEqual(renderer.playbackMonitor.state, .paused)
        renderer.stop()
        await drainMainQueue()
        XCTAssertEqual(renderer.playbackMonitor.state, .idle)
    }

    private enum FixtureError: Error { case encodingFailed }

    @MainActor
    func testProfilesThrottleDisplayLinkAtDifferentRefreshRates() async {
        for refreshRate in [59.94, 60, 120, 144] {
            for mode in PerformanceManager.PerformanceMode.allCases {
                var frames = 0
                let scheduler = DisplayLinkFrameScheduler(maximumFramesPerSecond: mode.maxFPS) { frames += 1 }
                for tick in 0..<Int(ceil(refreshRate * 2)) {
                    scheduler.requestFrame(at: Double(tick) / refreshRate)
                    await drainMainQueue()
                }
                XCTAssertEqual(Double(frames), Double(mode.maxFPS * 2), accuracy: 1,
                               "\(mode) at \(refreshRate) Hz")
                scheduler.invalidate()
            }
        }
    }

    @MainActor
    func testProfileChangeAndStallDoNotQueueCatchUpFramesOrReviveInvalidatedSession() async {
        var frames = 0
        let scheduler = DisplayLinkFrameScheduler(maximumFramesPerSecond: 60) { frames += 1 }
        scheduler.requestFrame(at: 0)
        scheduler.setMaximumFramesPerSecond(15)
        for tick in 1...500 { scheduler.requestFrame(at: Double(tick)) }
        await drainMainQueue()
        XCTAssertEqual(frames, 1, "A blocked main queue must coalesce pending work")
        scheduler.requestFrame(at: 600)
        await drainMainQueue()
        scheduler.requestFrame(at: 600.001)
        await drainMainQueue()
        XCTAssertEqual(frames, 2, "No burst after a stall")
        scheduler.requestFrame(at: 601)
        scheduler.invalidate()
        scheduler.setMaximumFramesPerSecond(60)
        await drainMainQueue()
        scheduler.requestFrame(at: 602)
        await drainMainQueue()
        XCTAssertEqual(frames, 2)
    }

    func testPerformancePreferenceSurvivesRelaunchAndAcceptsLegacyValues() throws {
        let suite = "PerformanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(PerformanceManager(defaults: defaults).mode, .balanced)
        for mode in PerformanceManager.PerformanceMode.allCases {
            PerformanceManager(defaults: defaults).mode = mode
            XCTAssertEqual(PerformanceManager(defaults: defaults).mode, mode)
        }
        defaults.set("balanced", forKey: "performance.mode")
        XCTAssertEqual(PerformanceManager(defaults: defaults).mode, .balanced)
        defaults.set("unknown", forKey: "performance.mode")
        XCTAssertEqual(PerformanceManager(defaults: defaults).mode, .balanced)
    }

    @MainActor
    func testProfileBindingUpdatesExistingAndNewDisplaysWithoutChangingPlayback() throws {
        let suite = "PerformanceBindingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = PerformanceManager(defaults: defaults)
        let first = ProfileRendererSpy()
        let second = ProfileRendererSpy()
        let firstBinding = manager.bind(to: first)
        let secondBinding = manager.bind(to: second)
        manager.mode = .battery
        let connectedLater = ProfileRendererSpy()
        let thirdBinding = manager.bind(to: connectedLater)
        XCTAssertEqual(first.modes, [.balanced, .battery])
        XCTAssertEqual(second.modes, [.balanced, .battery])
        XCTAssertEqual(connectedLater.modes, [.battery])
        firstBinding.cancel()
        manager.mode = .quality
        manager.mode = .quality
        XCTAssertEqual(first.modes, [.balanced, .battery], "Disconnected display must unsubscribe")
        XCTAssertEqual(second.modes, [.balanced, .battery, .quality])
        XCTAssertEqual(connectedLater.modes, [.battery, .quality])
        XCTAssertEqual(first.playbackMutations + second.playbackMutations + connectedLater.playbackMutations, 0)
        withExtendedLifetime([secondBinding, thirdBinding]) {}
    }

    @MainActor
    func testAVFoundationProfileChangesKeepNormalSpeedAndPreservePause() async throws {
        try await assertProfileChangesPreservePlayback(VideoRenderer())
    }

    @MainActor
    func testMetalProfileChangesKeepNormalSpeedAndPreservePause() async throws {
        guard MetalVideoRenderer.isSupported else { throw XCTSkip("Metal is unavailable") }
        try await assertProfileChangesPreservePlayback(MetalVideoRenderer())
    }

    @MainActor
    private func assertProfileChangesPreservePlayback(_ renderer: WallpaperRenderer) async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 96, height: 96), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let video = FileManager.default.temporaryDirectory.appendingPathComponent("profiles-\(UUID().uuidString).mov")
        defer {
            renderer.stop()
            window.contentView = nil
            window.close()
            try? FileManager.default.removeItem(at: video)
        }
        try await writeShortVideo(to: video, frames: 300, fps: 60)
        window.contentView = renderer.rendererView
        window.orderFront(nil)
        renderer.loadVideo(url: video)
        renderer.play()
        renderer.applyPerformanceMode(.battery) // Change during asynchronous load.
        let deadline = Date().addingTimeInterval(5)
        while (!renderer.hasPresentedFrame || (renderer.currentPlaybackTime ?? 0) < 0.1), Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(renderer.hasPresentedFrame)
        let layer = renderer.filterLayer as? AVPlayerLayer
        let originalItem = layer?.player?.currentItem
        if let originalItem {
            XCTAssertNil(originalItem.videoComposition, "AVPlayer fallback must keep native timing")
        }
        for mode in [PerformanceManager.PerformanceMode.quality, .battery, .balanced] {
            let start = try XCTUnwrap(renderer.currentPlaybackTime)
            renderer.applyPerformanceMode(mode)
            if let originalItem {
                XCTAssertTrue(layer?.player?.currentItem === originalItem, "A profile must not reload the player")
                XCTAssertNil(originalItem.videoComposition)
            }
            for _ in 0..<10 {
                try await Task.sleep(nanoseconds: 20_000_000)
                XCTAssertEqual(renderer.currentPlaybackRate, 1)
                XCTAssertTrue(renderer.hasPresentedFrame)
                if let layer {
                    XCTAssertTrue(layer.isReadyForDisplay, "Profile switching must retain displayed video")
                }
            }
            let elapsed = try XCTUnwrap(renderer.currentPlaybackTime) - start
            XCTAssertGreaterThan(elapsed, 0.15, "Lower frame rate must not slow the video timeline")
            renderer.pause()
            let pausedTime = try XCTUnwrap(renderer.currentPlaybackTime)
            renderer.applyPerformanceMode(.quality)
            try await Task.sleep(nanoseconds: 100_000_000)
            XCTAssertEqual(renderer.currentPlaybackRate, 0)
            XCTAssertEqual(renderer.currentPlaybackTime ?? -1, pausedTime, accuracy: 0.02)
            XCTAssertTrue(renderer.hasPresentedFrame)
            if let layer { XCTAssertNotNil(layer.displayedPixelBuffer(), "Paused frame must remain available") }
            renderer.play()
        }
    }
}

private final class ProfileRendererSpy: WallpaperRenderer {
    let playbackMonitor = RendererPlaybackMonitor()
    let rendererView = NSView()
    var modes: [PerformanceManager.PerformanceMode] = []
    var playbackMutations = 0
    let currentPlaybackTime: TimeInterval? = nil
    let currentPlaybackRate: Float = 0
    let hasPresentedFrame = false
    var onBecameReady: (() -> Void)?
    var filterLayer: CALayer? { nil }
    func applyPerformanceMode(_ mode: PerformanceManager.PerformanceMode) { modes.append(mode) }
    func loadVideo(url: URL) { playbackMutations += 1 }
    func play() { playbackMutations += 1 }
    func pause() { playbackMutations += 1 }
    func stop() { playbackMutations += 1 }
    func recoverPlayback() { playbackMutations += 1 }
    func maintainPlayback() { playbackMutations += 1 }
}
