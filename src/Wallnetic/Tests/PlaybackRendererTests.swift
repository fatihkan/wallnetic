import XCTest
import AVFoundation
import AppKit
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
        DispatchQueue.concurrentPerform(iterations: 500) { _ in scheduler.requestFrame() }
        await drainMainQueue()
        XCTAssertEqual(frames, 1)
        scheduler.requestFrame()
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

    private func writeShortVideo(to url: URL) async throws {
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
        for frame in 0..<3 {
            let deadline = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing, Date() < deadline else {
                    writer.cancelWriting()
                    throw writer.error ?? FixtureError.encodingFailed
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 10)) else {
                writer.cancelWriting()
                throw writer.error ?? FixtureError.encodingFailed
            }
        }
        writer.endSession(atSourceTime: CMTime(value: 3, timescale: 10))
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? FixtureError.encodingFailed }
    }

    private enum FixtureError: Error { case encodingFailed }
}
