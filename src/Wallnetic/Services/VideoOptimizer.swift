import AVFoundation
import VideoToolbox

@MainActor
protocol VideoOptimizing: AnyObject {
    func inspect(_ source: URL) async throws -> VideoOptimizationInfo
    func optimize(_ source: URL, preset: VideoOptimizationPreset, progress: @escaping (Double) -> Void) async throws -> OptimizedVideoResult
}

/// Native background export. Only a verified complete file is published to the library.
@MainActor
final class VideoOptimizer: VideoOptimizing {
    static let shared = VideoOptimizer(directory: { WallpaperLibrary.shared.libraryURL }, store: .shared)
    typealias Export = (AVAssetExportSession, @escaping (Double) -> Void) async throws -> Void
    private let directory: () -> URL
    private let store: OptimizedCopyStore
    private let capacity: (URL) throws -> Int64
    private let hevcSupported: (CGSize) -> Bool
    private let export: Export
    private var isWorking = false

    init(directory: @escaping () -> URL, store: OptimizedCopyStore,
         capacity: @escaping (URL) throws -> Int64 = VideoOptimizer.availableCapacity,
         hevcSupported: @escaping (CGSize) -> Bool = VideoOptimizer.supportsHEVC,
         export: @escaping Export = VideoOptimizer.exportSession) {
        self.directory = directory
        self.store = store
        self.capacity = capacity
        self.hevcSupported = hevcSupported
        self.export = export
    }

    private struct Source {
        let asset: AVURLAsset
        let track: AVAssetTrack
        let duration: CMTime
        let size: CGSize
        let transform: CGAffineTransform
        let fps: Double
        let bytes: Int64
        let modified: Date?
        let identifier: AnyHashable?
        let assumesSDR: Bool
    }

    private func read(_ url: URL) async throws -> Source {
        try Task.checkCancellation()
        guard url.isFileURL else { throw VideoOptimizationError.sourceChanged }
        var fresh = url
        fresh.removeAllCachedResourceValues()
        let attributes = try fresh.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey])
        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true, let bytes = attributes.fileSize, bytes > 0 else {
            throw VideoOptimizationError.sourceChanged
        }
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isExportable) else { throw VideoOptimizationError.unsupported("This video cannot be exported by macOS.") }
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard tracks.count == 1, let track = tracks.first else {
            throw VideoOptimizationError.unsupported("Optimization supports videos with a single video track.")
        }
        let duration = try await asset.load(.duration)
        guard duration.isNumeric, duration.seconds.isFinite, duration.seconds > 0, duration.seconds <= 86400 else {
            throw VideoOptimizationError.unsupported("Optimization supports finite videos up to 24 hours long.")
        }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let fps = Double(try await track.load(.nominalFrameRate))
        let formats = try await track.load(.formatDescriptions)
        let characteristics = try await track.load(.mediaCharacteristics)
        guard !formats.isEmpty else { throw VideoOptimizationError.unsupported("The video format could not be read.") }
        var assumesSDR = false
        for format in formats {
            let ext = CMFormatDescriptionGetExtensions(format) as? [String: Any] ?? [:]
            try Self.validateColor(ext, containsHDR: characteristics.contains(.containsHDRVideo))
            if ext[kCMFormatDescriptionExtension_ColorPrimaries as String] == nil || ext[kCMFormatDescriptionExtension_TransferFunction as String] == nil { assumesSDR = true }
            let dimensions = CMVideoFormatDescriptionGetPresentationDimensions(format, usePixelAspectRatio: true, useCleanAperture: false)
            let encoded = CMVideoFormatDescriptionGetDimensions(format)
            guard abs(dimensions.width - Double(encoded.width)) < 1, abs(dimensions.height - Double(encoded.height)) < 1 else {
                throw VideoOptimizationError.unsupported("Anamorphic video is not supported by these presets. Keep using the original.")
            }
        }
        _ = try VideoOptimizationGeometry.make(size: size, transform: transform, fps: fps, preset: .balanced)
        try Task.checkCancellation()
        return Source(asset: asset, track: track, duration: duration, size: size, transform: transform, fps: fps,
                      bytes: Int64(bytes), modified: attributes.contentModificationDate,
                      identifier: attributes.fileResourceIdentifier as? AnyHashable, assumesSDR: assumesSDR)
    }

    /// Explicitly limit this first implementation to SDR Rec.709 / untagged SDR.
    static func validateColor(_ ext: [String: Any], containsHDR: Bool) throws {
        let fields: [(CFString, String)] = [
            (kCMFormatDescriptionExtension_ColorPrimaries, AVVideoColorPrimaries_ITU_R_709_2),
            (kCMFormatDescriptionExtension_TransferFunction, AVVideoTransferFunction_ITU_R_709_2),
            (kCMFormatDescriptionExtension_YCbCrMatrix, AVVideoYCbCrMatrix_ITU_R_709_2)
        ]
        let unsupported = fields.contains { key, expected in
            guard let raw = ext[key as String] else { return false }
            guard let value = raw as? String else { return true }
            return value != expected
        }
        guard !containsHDR, !unsupported,
              (ext[kCMFormatDescriptionExtension_ContainsAlphaChannel as String] as? Bool) != true,
              ext[kCMFormatDescriptionExtension_MasteringDisplayColorVolume as String] == nil,
              ext[kCMFormatDescriptionExtension_ContentLightLevelInfo as String] == nil else {
            throw VideoOptimizationError.unsupported("HDR, transparency and color-tagged formats other than SDR Rec.709 are not supported by these presets. Keep using the original video.")
        }
    }

    func inspect(_ url: URL) async throws -> VideoOptimizationInfo {
        let source = try await read(url)
        var unavailable: [VideoOptimizationPreset: String] = [:]
        for preset in VideoOptimizationPreset.allCases {
            let geometry = try VideoOptimizationGeometry.make(size: source.size, transform: source.transform, fps: source.fps, preset: preset)
            if preset == .hevc && !hevcSupported(geometry.size) {
                unavailable[preset] = "This Mac does not provide HEVC hardware encoding and decoding for this size. Choose H.264."
            } else if !(await AVAssetExportSession.compatibility(ofExportPreset: preset.exportPreset, with: source.asset, outputFileType: .mp4)) {
                unavailable[preset] = "macOS cannot export this video with the selected codec. Try another preset."
            }
            try Task.checkCancellation()
        }
        return VideoOptimizationInfo(duration: source.duration.seconds, size: CGRect(origin: .zero, size: source.size).applying(source.transform).standardized.size,
            frameRate: source.fps, sourceBytes: source.bytes, unavailable: unavailable, assumesSDR: source.assumesSDR)
    }

    func optimize(_ url: URL, preset: VideoOptimizationPreset, progress: @escaping (Double) -> Void) async throws -> OptimizedVideoResult {
        guard !isWorking else { throw VideoOptimizationError.busy }
        isWorking = true
        defer { isWorking = false }
        let source = try await read(url)
        let geometry = try VideoOptimizationGeometry.make(size: source.size, transform: source.transform, fps: source.fps, preset: preset)
        if preset == .hevc && !hevcSupported(geometry.size) {
            throw VideoOptimizationError.unsupported("HEVC hardware encoding/decoding is unavailable for this video size. Choose H.264.")
        }
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoOptimizationError.failed("Could not create the video track.")
        }
        let timeRange = CMTimeRange(start: .zero, duration: source.duration)
        try track.insertTimeRange(timeRange, of: source.track, at: .zero)
        let video = AVMutableVideoComposition()
        video.renderSize = geometry.size
        video.frameDuration = geometry.frameDuration
        video.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        video.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        video.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(geometry.transform, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange
        instruction.layerInstructions = [layer]
        video.instructions = [instruction]
        guard await AVAssetExportSession.compatibility(ofExportPreset: preset.exportPreset, with: composition, outputFileType: .mp4),
              let session = AVAssetExportSession(asset: composition, presetName: preset.exportPreset) else {
            throw VideoOptimizationError.unsupported("macOS cannot export this video with the selected preset.")
        }
        session.videoComposition = video
        session.timeRange = timeRange
        session.outputFileType = .mp4
        let destination = directory().standardizedFileURL.resolvingSymlinksInPath()
        guard destination.isFileURL else { throw VideoOptimizationError.failed("The library directory is unavailable.") }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        // Estimate is not a savings promise; leave headroom for the encoder and container.
        let estimate = (try? await session.estimatedOutputFileLengthInBytes) ?? 0
        let fallback = Int64(source.duration.seconds * 20_000_000 / 8)
        let budget = max(estimate, fallback)
        let required = budget.addingReportingOverflow(128 * 1024 * 1024)
        guard !required.overflow else { throw VideoOptimizationError.cannotCheckSpace }
        guard try capacity(destination) >= required.partialValue else { throw VideoOptimizationError.diskSpace(required.partialValue) }
        try Task.checkCancellation()
        let staging = destination.appendingPathComponent(".optimization-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        var unpublishedFinal: URL?
        let output = staging.appendingPathComponent("output.mp4")
        session.outputURL = output
        session.directoryForTemporaryFiles = staging
        progress(0)
        do {
            try await export(session) { progress(min(0.95, max(0, $0 * 0.95))) }
            try Task.checkCancellation()
            guard try sourceUnchanged(url, source: source) else { throw VideoOptimizationError.sourceChanged }
            let result = try await verify(output, source: source, geometry: geometry, preset: preset)
            try Task.checkCancellation()
            guard try sourceUnchanged(url, source: source) else { throw VideoOptimizationError.sourceChanged }
            // No suspension from this point to publication: cancellation cannot
            // interleave a move and relationship write, or expose a partial file.
            let final = destination.appendingPathComponent(Self.outputName(source: url, preset: preset))
            try FileManager.default.moveItem(at: output, to: final)
            unpublishedFinal = final
            try FileManager.default.removeItem(at: staging)
            try store.record(OptimizedCopyRecord(sourcePath: url.path, copyPath: final.path, preset: preset))
            unpublishedFinal = nil
            progress(1)
            return OptimizedVideoResult(url: final, sourceBytes: source.bytes, outputBytes: result.outputBytes,
                                        duration: result.duration, size: result.size, frameRate: result.frameRate)
        } catch {
            let failure = error
            do {
                if let unpublishedFinal { try FileManager.default.removeItem(at: unpublishedFinal) }
                if FileManager.default.fileExists(atPath: staging.path) { try FileManager.default.removeItem(at: staging) }
            } catch {
                throw VideoOptimizationError.failed("Conversion stopped, but temporary files could not be removed. Check the library disk and remove the temporary .optimization folder. " + error.localizedDescription)
            }
            if Task.isCancelled || failure is CancellationError { throw CancellationError() }
            throw failure
        }
    }

    private func sourceUnchanged(_ url: URL, source: Source) throws -> Bool {
        var fresh = url
        fresh.removeAllCachedResourceValues()
        let values = try fresh.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey])
        return values.isRegularFile == true && values.isSymbolicLink != true && values.fileSize.map(Int64.init) == source.bytes && values.contentModificationDate == source.modified &&
            (values.fileResourceIdentifier as? AnyHashable) == source.identifier
    }

    private func verify(_ output: URL, source: Source, geometry: VideoOptimizationGeometry, preset: VideoOptimizationPreset) async throws -> OptimizedVideoResult {
        let asset = AVURLAsset(url: output)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw VideoOptimizationError.invalidOutput }
        let duration = try await asset.load(.duration).seconds
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let fps = Double(try await track.load(.nominalFrameRate))
        let formats = try await track.load(.formatDescriptions)
        let expectedCodec = preset == .hevc ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264
        let tolerance = max(0.05, geometry.frameDuration.seconds + 0.01)
        let bytes = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard duration.isFinite, abs(duration - source.duration.seconds) <= tolerance,
              size == geometry.size, transform.isIdentity, fps.isFinite, fps > 0,
              abs(fps - 1 / geometry.frameDuration.seconds) < 0.2,
              !formats.isEmpty, formats.allSatisfy({ CMFormatDescriptionGetMediaSubType($0) == expectedCodec }), bytes > 0 else {
            throw VideoOptimizationError.invalidOutput
        }
        for format in formats { try Self.validateColor(CMFormatDescriptionGetExtensions(format) as? [String: Any] ?? [:], containsHDR: false) }
        return OptimizedVideoResult(url: output, sourceBytes: source.bytes, outputBytes: Int64(bytes), duration: duration, size: size, frameRate: fps)
    }

    static func outputName(source: URL, preset: VideoOptimizationPreset) -> String {
        let name = String(decoding: source.deletingPathExtension().lastPathComponent.utf8.prefix(80), as: UTF8.self)
        return name + " - Optimized " + preset.filenameLabel + " - " + UUID().uuidString + ".mp4"
    }
    nonisolated static func availableCapacity(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        guard let bytes = values.volumeAvailableCapacityForImportantUsage ?? values.volumeAvailableCapacity.map(Int64.init) else {
            throw VideoOptimizationError.cannotCheckSpace
        }
        return bytes
    }
    nonisolated static func supportsHEVC(_ size: CGSize) -> Bool {
        guard VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC) else { return false }
        let specification = [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true] as CFDictionary
        return VTCopySupportedPropertyDictionaryForEncoder(width: Int32(size.width), height: Int32(size.height), codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: specification, encoderIDOut: nil, supportedPropertiesOut: nil) == noErr
    }

    static func exportSession(_ session: AVAssetExportSession, progress: @escaping (Double) -> Void) async throws {
        let control = OptimizationExportControl()
        let monitor = Task { @MainActor in
            while !Task.isCancelled {
                progress(Double(session.progress))
                do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
            }
        }
        defer { monitor.cancel() }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if !control.start(session, completion: { continuation.resume() }) { continuation.resume() }
            }
        } onCancel: { control.cancel() }
        try Task.checkCancellation()
        guard session.status == .completed else {
            if session.status == .cancelled { throw CancellationError() }
            if isOutOfSpace(session.error) {
                throw VideoOptimizationError.failed("The library disk ran out of space during conversion. Free some space and try again.")
            }
            throw VideoOptimizationError.failed(session.error?.localizedDescription ?? "The encoder did not complete.")
        }
    }

    static func isOutOfSpace(_ error: Error?, depth: Int = 0) -> Bool {
        guard let error = error as NSError?, depth < 8 else { return false }
        if (error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError) ||
            (error.domain == NSPOSIXErrorDomain && error.code == ENOSPC) ||
            (error.domain == AVFoundationErrorDomain && error.code == AVError.diskFull.rawValue) { return true }
        return isOutOfSpace(error.userInfo[NSUnderlyingErrorKey] as? Error, depth: depth + 1)
    }
}

/// Serializes start/cancel, including cancellation just before export begins.
private final class OptimizationExportControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var session: AVAssetExportSession?
    func start(_ session: AVAssetExportSession, completion: @escaping () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return false }
        self.session = session
        session.exportAsynchronously(completionHandler: completion)
        return true
    }
    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        session?.cancelExport()
    }
}
