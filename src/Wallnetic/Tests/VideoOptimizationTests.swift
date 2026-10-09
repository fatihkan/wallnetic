import XCTest
import AVFoundation
import AppKit
import CryptoKit
@testable import Wallnetic

@MainActor
final class VideoOptimizationTests: XCTestCase {
    private var root: URL!
    private var destination: URL!
    private var suite: String!
    private var defaults: UserDefaults!
    private var store: OptimizedCopyStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("OptimizationTests-" + UUID().uuidString)
        destination = root.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        suite = "VideoOptimizationTests." + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        store = OptimizedCopyStore(defaults: defaults)
    }
    override func tearDownWithError() throws {
        if let defaults, let suite { defaults.removePersistentDomain(forName: suite) }
        if let root, FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }
    private func optimizer(capacity: Int64 = Int64.max, hevc: Bool = false, export: @escaping VideoOptimizer.Export = VideoOptimizer.exportSession) -> VideoOptimizer {
        VideoOptimizer(directory: { self.destination }, store: store, capacity: { _ in capacity }, hevcSupported: { _ in hevc }, export: export)
    }
    private func contents() throws -> [URL] { try FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil) }

    func testGeometryRespectsPortraitLandscapeAndNoUpscaling() throws {
        let landscape = try VideoOptimizationGeometry.make(size: CGSize(width: 3840, height: 2160), transform: .identity, fps: 60, preset: .compact)
        XCTAssertEqual(landscape.size, CGSize(width: 1280, height: 720))
        XCTAssertEqual(landscape.frameDuration.seconds, 1 / 15.0, accuracy: 0.00001)
        let rotation = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 2160, ty: 0)
        let portrait = try VideoOptimizationGeometry.make(size: CGSize(width: 3840, height: 2160), transform: rotation, fps: 60, preset: .balanced)
        XCTAssertEqual(portrait.size, CGSize(width: 1080, height: 1920))
        let rect = CGRect(x: 0, y: 0, width: 3840, height: 2160).applying(portrait.transform).standardized
        XCTAssertEqual(rect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 0, accuracy: 0.001)
        XCTAssertEqual(rect.size, portrait.size)
        let small = try VideoOptimizationGeometry.make(size: CGSize(width: 642, height: 360), transform: .identity, fps: 12, preset: .balanced)
        XCTAssertEqual(small.size, CGSize(width: 642, height: 360))
        XCTAssertEqual(small.frameDuration.seconds, 1 / 12.0, accuracy: 0.00001)
    }
    func testGeometryRejectsUnboundedOrSingularInputAndNormalizesMirroring() throws {
        for size in [CGSize(width: 0, height: 10), CGSize(width: CGFloat.infinity, height: 10), CGSize(width: 20000, height: 10)] {
            XCTAssertThrowsError(try VideoOptimizationGeometry.make(size: size, transform: .identity, fps: 30, preset: .balanced))
        }
        XCTAssertThrowsError(try VideoOptimizationGeometry.make(size: CGSize(width: 640, height: 360), transform: CGAffineTransform(scaleX: 0, y: 1), fps: 30, preset: .balanced))
        let mirror = CGAffineTransform(scaleX: -1, y: 1)
        let result = try VideoOptimizationGeometry.make(size: CGSize(width: 640, height: 360), transform: mirror, fps: 29.97, preset: .balanced)
        XCTAssertEqual(CGRect(x: 0, y: 0, width: 640, height: 360).applying(result.transform).minX, 0)
        XCTAssertEqual(1 / result.frameDuration.seconds, 29.97, accuracy: 0.01)
    }
    func testHDRWideGamutAndMalformedTagsAreRejected() {
        XCTAssertNoThrow(try VideoOptimizer.validateColor([:], containsHDR: false))
        XCTAssertNoThrow(try VideoOptimizer.validateColor([kCMFormatDescriptionExtension_ColorPrimaries as String: AVVideoColorPrimaries_ITU_R_709_2], containsHDR: false))
        XCTAssertThrowsError(try VideoOptimizer.validateColor([:], containsHDR: true))
        for tags: [String: Any] in [
            [kCMFormatDescriptionExtension_TransferFunction as String: AVVideoTransferFunction_SMPTE_ST_2084_PQ],
            [kCMFormatDescriptionExtension_TransferFunction as String: AVVideoTransferFunction_ITU_R_2100_HLG],
            [kCMFormatDescriptionExtension_ColorPrimaries as String: AVVideoColorPrimaries_P3_D65],
            [kCMFormatDescriptionExtension_ColorPrimaries as String: 123],
            [kCMFormatDescriptionExtension_MasteringDisplayColorVolume as String: Data([1])]
        ] { XCTAssertThrowsError(try VideoOptimizer.validateColor(tags, containsHDR: false)) }
    }
    func testNestedDiskFullErrorsAreRecognized() {
        let underlying = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        let wrapped = NSError(domain: AVFoundationErrorDomain, code: -11800, userInfo: [NSUnderlyingErrorKey: underlying])
        XCTAssertTrue(VideoOptimizer.isOutOfSpace(wrapped))
        XCTAssertFalse(VideoOptimizer.isOutOfSpace(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)))
    }
    func testNativeExportCancellationRemovesTemporaryOutput() async throws {
        let source = try await fixture()
        let service = optimizer()
        var task: Task<OptimizedVideoResult, Error>?
        var callbacks = 0
        task = Task {
            try await service.optimize(source, preset: .compact) { _ in
                callbacks += 1
                if callbacks == 2 { task?.cancel() }
            }
        }
        do { _ = try await task!.value; XCTFail("Expected native export cancellation") }
        catch is CancellationError { }
        XCTAssertGreaterThanOrEqual(callbacks, 2)
        XCTAssertTrue(try contents().isEmpty)
        XCTAssertTrue(store.records.isEmpty)
    }
    func testOutputNamesAreUniqueAndStayWithinOneDirectory() {
        let source = URL(fileURLWithPath: "/private/" + String(repeating: "🌄", count: 100) + ".mov")
        let a = VideoOptimizer.outputName(source: source, preset: .compact)
        let b = VideoOptimizer.outputName(source: source, preset: .compact)
        XCTAssertNotEqual(a, b)
        XCTAssertLessThan(a.utf8.count, 255)
        XCTAssertFalse(a.contains("/"))
        XCTAssertTrue(a.hasSuffix(".mp4"))
    }

    func testRealH264ExportPreservesSourceDurationMotionAndSDRColors() async throws {
        let source = try await fixture()
        let original = try Data(contentsOf: source)
        let service = optimizer()
        let info = try await service.inspect(source)
        XCTAssertNil(info.unavailable[.compact])
        XCTAssertNotNil(info.unavailable[.hevc])
        XCTAssertFalse(info.assumesSDR)
        var progress: [Double] = []
        let result = try await service.optimize(source, preset: .compact) { progress.append($0) }
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: source)), SHA256.hash(data: original))
        XCTAssertEqual(result.duration, 1, accuracy: 0.07)
        XCTAssertEqual(result.size, CGSize(width: 640, height: 360))
        XCTAssertEqual(result.frameRate, 15, accuracy: 0.1)
        XCTAssertEqual(progress.last, 1)
        XCTAssertTrue(progress.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertEqual(try contents().map { $0.resolvingSymlinksInPath() }, [result.url.resolvingSymlinksInPath()], "No partial directories survive success")
        XCTAssertEqual(store.originalPath(for: result.url), source.path)
        let outputTracks = try await AVURLAsset(url: result.url).loadTracks(withMediaType: .audio)
        XCTAssertTrue(outputTracks.isEmpty)
        for time in [0.2, 0.8] {
            let sourceFrame = try frameBytes(source, at: time)
            let outputFrame = try frameBytes(result.url, at: time)
            let meanError = zip(sourceFrame, outputFrame).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(sourceFrame.count * 255)
            XCTAssertLessThan(meanError, 0.08, "Matching timestamps must keep motion timing and SDR colors")
        }
        XCTAssertNotEqual(try frameBytes(result.url, at: 0.2), try frameBytes(result.url, at: 0.8), "Motion must not freeze")
    }
    func testRealRotatedVideoProducesUprightPortraitCopy() async throws {
        let source = try await fixture(transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 360, ty: 0))
        let result = try await optimizer().optimize(source, preset: .balanced) { _ in }
        XCTAssertEqual(result.size, CGSize(width: 360, height: 640))
        XCTAssertEqual(result.frameRate, 30, accuracy: 0.1)
        let sourceFrame = try frameBytes(source, at: 0.2)
        let outputFrame = try frameBytes(result.url, at: 0.2)
        let error = zip(sourceFrame, outputFrame).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(sourceFrame.count * 255)
        XCTAssertLessThan(error, 0.08, "Orientation must be baked into the output pixels")
    }
    func testNativeHEVCWhenHardwareSupportsIt() async throws {
        let source = try await fixture()
        guard VideoOptimizer.supportsHEVC(CGSize(width: 640, height: 360)) else { throw XCTSkip("Runner has no compatible HEVC hardware encoder/decoder") }
        let result = try await optimizer(hevc: true).optimize(source, preset: .hevc) { _ in }
        XCTAssertEqual(result.frameRate, 30, accuracy: 0.1)
        XCTAssertEqual(result.duration, 1, accuracy: 0.05)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testInsufficientSpaceFailsBeforeExportAndLeavesNoPartialFiles() async throws {
        let source = try await fixture()
        var exported = false
        let service = optimizer(capacity: 0) { _, _ in exported = true }
        do { _ = try await service.optimize(source, preset: .compact) { _ in }; XCTFail("Expected disk-space failure") }
        catch VideoOptimizationError.diskSpace { }
        XCTAssertFalse(exported)
        XCTAssertTrue(try contents().isEmpty)
        XCTAssertTrue(store.records.isEmpty)
    }
    func testUnavailableHEVCNeverStartsConversion() async throws {
        let source = try await fixture()
        var exported = false
        let service = optimizer { _, _ in exported = true }
        do { _ = try await service.optimize(source, preset: .hevc) { _ in }; XCTFail("Expected unsupported hardware") }
        catch VideoOptimizationError.unsupported { }
        XCTAssertFalse(exported)
        XCTAssertTrue(try contents().isEmpty)
    }
    func testFailureAndCancellationRemovePartialFilesAndKeepSource() async throws {
        let source = try await fixture()
        let original = try Data(contentsOf: source)
        for cancelled in [false, true] {
            let service = optimizer { session, _ in
                try Data([1, 2, 3]).write(to: XCTUnwrap(session.outputURL))
                if cancelled { throw CancellationError() }
                throw VideoOptimizationError.failed("Injected encoder failure")
            }
            do { _ = try await service.optimize(source, preset: .compact) { _ in }; XCTFail("Expected failure") }
            catch { XCTAssertEqual(error is CancellationError, cancelled) }
            XCTAssertTrue(try contents().isEmpty)
            XCTAssertEqual(try Data(contentsOf: source), original)
            XCTAssertTrue(store.records.isEmpty)
        }
    }
    func testTaskCancellationWaitsForExporterThenCleansUp() async throws {
        let source = try await fixture()
        let started = expectation(description: "Export started")
        let service = optimizer { session, _ in
            try Data([1, 2, 3]).write(to: XCTUnwrap(session.outputURL))
            started.fulfill()
            try await Task.sleep(nanoseconds: 30_000_000_000)
        }
        let task = Task { try await service.optimize(source, preset: .compact) { _ in } }
        await fulfillment(of: [started], timeout: 10)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
        XCTAssertTrue(try contents().isEmpty)
        XCTAssertTrue(store.records.isEmpty)
    }
    func testInvalidCompletedOutputIsNotPublished() async throws {
        let source = try await fixture()
        let service = optimizer { session, _ in try Data([1, 2, 3]).write(to: XCTUnwrap(session.outputURL)) }
        do { _ = try await service.optimize(source, preset: .compact) { _ in }; XCTFail("Expected validation failure") } catch { }
        XCTAssertTrue(try contents().isEmpty)
        XCTAssertTrue(store.records.isEmpty)
    }
    func testChangedSourceIsRejectedBeforePublishing() async throws {
        let source = try await fixture()
        let service = optimizer { session, progress in
            try await VideoOptimizer.exportSession(session, progress: progress)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: source.path)
        }
        do { _ = try await service.optimize(source, preset: .compact) { _ in }; XCTFail("Expected changed source") }
        catch VideoOptimizationError.sourceChanged { }
        XCTAssertTrue(try contents().isEmpty)
    }
    func testConcurrentConversionIsRejected() async throws {
        let source = try await fixture()
        let started = expectation(description: "Export started")
        let service = optimizer { _, _ in started.fulfill(); try await Task.sleep(nanoseconds: 30_000_000_000) }
        let first = Task { try await service.optimize(source, preset: .compact) { _ in } }
        await fulfillment(of: [started], timeout: 10)
        do { _ = try await service.optimize(source, preset: .balanced) { _ in }; XCTFail("Expected busy") }
        catch VideoOptimizationError.busy { }
        first.cancel()
        _ = try? await first.value
        XCTAssertTrue(try contents().isEmpty)
    }
    func testSourceAndOptimizedCopiesHaveIndependentRelationships() throws {
        let source = root.appendingPathComponent("original.mp4")
        let a = destination.appendingPathComponent("a.mp4"), b = destination.appendingPathComponent("b.mp4")
        try store.record(OptimizedCopyRecord(sourcePath: source.path, copyPath: a.path, preset: .compact))
        try store.record(OptimizedCopyRecord(sourcePath: source.path, copyPath: b.path, preset: .balanced))
        store.removeCopies(at: [a.path])
        let restored = OptimizedCopyStore(defaults: defaults)
        XCTAssertNil(restored.originalPath(for: a))
        XCTAssertEqual(restored.originalPath(for: b), source.path)
        restored.removeCopies(at: [source.path])
        XCTAssertEqual(restored.records.count, 1, "Removing an original must not delete its copies")
    }
    func testCorruptRelationshipStoreIsBackedUpOnNewCopy() throws {
        let bad = Data("invalid".utf8)
        defaults.set(bad, forKey: OptimizedCopyStore.key)
        let restored = OptimizedCopyStore(defaults: defaults)
        XCTAssertEqual(defaults.data(forKey: OptimizedCopyStore.key), bad)
        try restored.record(OptimizedCopyRecord(sourcePath: "/a.mp4", copyPath: "/b.mp4", preset: .compact))
        XCTAssertEqual(defaults.data(forKey: OptimizedCopyStore.key + ".recoveryBackup"), bad)
    }

    private func fixture(transform: CGAffineTransform = .identity) async throws -> URL {
        let url = root.appendingPathComponent(UUID().uuidString + ".mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 640, AVVideoHeightKey: 360,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_000_000, AVVideoAllowFrameReorderingKey: false],
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]
        ])
        input.transform = transform
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 640, kCVPixelBufferHeightKey as String: 360,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error! }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<60 {
            var attempts = 0
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing, attempts < 1000 else { throw VideoOptimizationError.failed("Test fixture encoder stalled") }
                attempts += 1
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            var buffer: CVPixelBuffer?
            guard let pool = adapter.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                  let buffer else { throw VideoOptimizationError.failed("Test pixel buffer unavailable") }
            CVPixelBufferLockBaseAddress(buffer, [])
            let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
            let address = CVPixelBufferGetBaseAddress(buffer)!
            for y in 0..<360 {
                let pixels = address.advanced(by: rowBytes * y).assumingMemoryBound(to: UInt32.self)
                for x in 0..<640 {
                    pixels[x] = x < 320 ? (frame < 30 ? 0xFFE03020 : 0xFF20C040) : (y < 180 ? 0xFF2030C0 : 0xFFD0C020)
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adapter.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 60)) else { throw writer.error! }
        }
        writer.endSession(atSourceTime: CMTime(value: 1, timescale: 1))
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error! }
        return url
    }
    private func frameBytes(_ url: URL, at seconds: Double) throws -> [UInt8] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil)
        var bytes = [UInt8](repeating: 0, count: 64 * 64 * 4)
        bytes.withUnsafeMutableBytes { data in
            let context = CGContext(data: data.baseAddress, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        return bytes
    }
}
