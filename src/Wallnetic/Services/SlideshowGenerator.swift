import Foundation
import AVFoundation
import Photos
import AppKit

/// Generates an MP4 slideshow from a list of `PHAsset`s with optional
/// Ken Burns pan/zoom and crossfade transitions (#137).
///
/// Render strategy:
/// 1. Load each PHAsset as a high-quality `NSImage`.
/// 2. Compute total output frames `N*d − (N−1)*T` and walk a single
///    timeline. For each frame, decide which 1–2 photos are visible
///    and render with their Ken Burns transforms + alpha blend.
/// 3. Pixel buffers go through `AVAssetWriterInputPixelBufferAdaptor`
///    to an H.264 `AVAssetWriter`.
///
/// Not main-actor isolated — the render loop is heavy and would freeze
/// the UI if forced onto main. Cancellation is cooperative via Swift
/// `Task.checkCancellation()`.
final class SlideshowGenerator {
    enum Resolution {
        case hd1080, qhd1440, uhd4k

        var size: CGSize {
            switch self {
            case .hd1080: return CGSize(width: 1920, height: 1080)
            case .qhd1440: return CGSize(width: 2560, height: 1440)
            case .uhd4k: return CGSize(width: 3840, height: 2160)
            }
        }

        var bitrate: Int {
            switch self {
            case .hd1080: return 8_000_000
            case .qhd1440: return 14_000_000
            case .uhd4k: return 24_000_000
            }
        }
    }

    enum Transition {
        case none, crossfade
    }

    struct Settings {
        var perPhotoDuration: TimeInterval = 5.0
        var transition: Transition = .crossfade
        var transitionDuration: TimeInterval = 0.6
        var kenBurns: Bool = true
        var resolution: Resolution = .hd1080
        var fps: Int32 = 30
    }

    enum GeneratorError: LocalizedError {
        case noAssets
        case writerFailed(String)
        case imageLoadFailed
        case cancelled

        var errorDescription: String? {
            switch self {
            case .noAssets: return "No photos selected."
            case .writerFailed(let m): return "Video writer failed: \(m)"
            case .imageLoadFailed: return "Could not load any of the selected photos."
            case .cancelled: return "Slideshow generation was cancelled."
            }
        }
    }

    /// Cover-fit oversampling so Ken Burns pan never exposes black
    /// edges at the minimum scale. `panRange = intensity * 80px` at the
    /// canvas, `coverPad` keeps a safety margin around the cropped area.
    private let coverPad: CGFloat = 1.12

    private let library: PhotosLibraryService

    init(library: PhotosLibraryService = .shared) {
        self.library = library
    }

    // MARK: - Public

    /// Generates the slideshow and writes it to a temporary file. The
    /// returned URL points at a `.mp4` ready to be imported via the
    /// `WallpaperManager` import flow.
    ///
    /// Cancel by cancelling the parent `Task` — the loop checks
    /// `Task.checkCancellation()` per frame and throws `cancelled`.
    func generate(
        assets: [PHAsset],
        settings: Settings,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        guard !assets.isEmpty else { throw GeneratorError.noAssets }

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Wallnetic-Slideshow-\(UUID().uuidString).mp4")

        // Load all images upfront. Slideshow counts realistically stay under 50.
        // Skip nil images so a single bad asset doesn't fail the whole job.
        var images: [NSImage] = []
        for (idx, asset) in assets.enumerated() {
            try Task.checkCancellation()
            if let img = await library.requestFullImage(for: asset) {
                images.append(img)
            }
            progress(Double(idx + 1) / Double(assets.count) * 0.2)
        }
        guard !images.isEmpty else { throw GeneratorError.imageLoadFailed }

        do {
            try await renderToFile(
                images: images,
                settings: settings,
                outputURL: outputURL,
                progress: { progress(0.2 + $0 * 0.8) }
            )
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: outputURL)
            throw GeneratorError.cancelled
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }

        return outputURL
    }

    // MARK: - Render pipeline

    private func renderToFile(
        images: [NSImage],
        settings: Settings,
        outputURL: URL,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws {
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let outputSize = settings.resolution.size

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outputSize.width,
            AVVideoHeightKey: outputSize.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: settings.resolution.bitrate,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let pixelBufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: outputSize.width,
            kCVPixelBufferHeightKey as String: outputSize.height
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: pixelBufferAttrs
        )

        guard writer.canAdd(writerInput) else {
            throw GeneratorError.writerFailed("input not accepted")
        }
        writer.add(writerInput)

        guard writer.startWriting() else {
            throw GeneratorError.writerFailed(writer.error?.localizedDescription ?? "startWriting failed")
        }
        writer.startSession(atSourceTime: .zero)

        try await renderFrames(
            images: images,
            settings: settings,
            adaptor: adaptor,
            writerInput: writerInput,
            outputSize: outputSize,
            progress: progress
        )

        writerInput.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            throw GeneratorError.writerFailed(writer.error?.localizedDescription ?? "unknown")
        }
    }

    /// Frame-by-frame timeline walker. Computes which 1–2 photos are
    /// visible at each output frame and renders accordingly.
    private func renderFrames(
        images: [NSImage],
        settings: Settings,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        writerInput: AVAssetWriterInput,
        outputSize: CGSize,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws {
        let fps = settings.fps
        let frameDuration = CMTime(value: 1, timescale: fps)
        let framesPerImage = Int(settings.perPhotoDuration * Double(fps))
        let transitionFrames = settings.transition == .crossfade
            ? min(Int(settings.transitionDuration * Double(fps)), framesPerImage / 2)
            : 0
        // Stride between successive photo starts. `framesPerImage − transitionFrames`
        // because adjacent photos overlap during their transition.
        let stride = framesPerImage - transitionFrames
        let imageCount = images.count
        let totalFrames = imageCount * framesPerImage - transitionFrames * (imageCount - 1)

        let kenBurns = generateKenBurnsTransforms(
            count: imageCount,
            intensity: settings.kenBurns ? 0.18 : 0
        )

        for f in 0..<totalFrames {
            try Task.checkCancellation()

            // Wait for adaptor to be ready without blocking main.
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
                try Task.checkCancellation()
            }

            // Determine which photo(s) are visible at this frame.
            // Photo i runs frames [i*stride, i*stride + framesPerImage).
            let primaryIdx = min(f / max(stride, 1), imageCount - 1)
            let frameInPrimary = f - primaryIdx * stride

            // Crossfade region: first `transitionFrames` frames of any non-first photo.
            let inOverlap = primaryIdx > 0 && transitionFrames > 0 && frameInPrimary < transitionFrames

            let primaryProgress = Double(frameInPrimary) / Double(max(framesPerImage, 1))
            let primaryTransform = kenBurns[primaryIdx].apply(progress: primaryProgress)

            let primaryAlpha: CGFloat
            let secondaryImage: NSImage?
            let secondaryTransform: CGAffineTransform?
            let secondaryAlpha: CGFloat

            if inOverlap {
                let t = CGFloat(frameInPrimary) / CGFloat(transitionFrames)
                primaryAlpha = t
                secondaryAlpha = 1 - t
                secondaryImage = images[primaryIdx - 1]
                let secondaryFrameInImage = stride + frameInPrimary
                let secProgress = Double(secondaryFrameInImage) / Double(max(framesPerImage, 1))
                secondaryTransform = kenBurns[primaryIdx - 1].apply(progress: secProgress)
            } else {
                primaryAlpha = 1
                secondaryImage = nil
                secondaryTransform = nil
                secondaryAlpha = 0
            }

            guard let pool = adaptor.pixelBufferPool,
                  let buffer = makePixelBuffer(pool: pool) else {
                throw GeneratorError.writerFailed("could not allocate pixel buffer")
            }

            drawFrame(
                into: buffer,
                outputSize: outputSize,
                primary: images[primaryIdx],
                primaryTransform: primaryTransform,
                primaryAlpha: primaryAlpha,
                secondary: secondaryImage,
                secondaryTransform: secondaryTransform,
                secondaryAlpha: secondaryAlpha
            )

            let pts = CMTimeMultiply(frameDuration, multiplier: Int32(f))
            if !adaptor.append(buffer, withPresentationTime: pts) {
                throw GeneratorError.writerFailed("append failed at frame \(f)")
            }

            progress(Double(f + 1) / Double(totalFrames))
        }
    }

    // MARK: - Ken Burns

    private struct KenBurns {
        var startScale: CGFloat
        var endScale: CGFloat
        var startOffset: CGPoint
        var endOffset: CGPoint

        /// Returns a transform that, when applied to an image already centered
        /// at the output's center, produces the desired scale + offset for the
        /// given progress value (0...1).
        func apply(progress: Double) -> CGAffineTransform {
            let p = max(0, min(1, progress))
            let scale = startScale + (endScale - startScale) * CGFloat(p)
            let offsetX = startOffset.x + (endOffset.x - startOffset.x) * CGFloat(p)
            let offsetY = startOffset.y + (endOffset.y - startOffset.y) * CGFloat(p)
            return CGAffineTransform(translationX: offsetX, y: offsetY).scaledBy(x: scale, y: scale)
        }
    }

    private func generateKenBurnsTransforms(count: Int, intensity: CGFloat) -> [KenBurns] {
        var seed = SystemRandomNumberGenerator()
        return (0..<count).map { _ in
            let zoomIn = Bool.random(using: &seed)
            // Always start ≥ 1.0 — combined with `coverPad` oversampling in
            // drawImage this prevents black edges from pan + scale.
            let startScale: CGFloat = zoomIn ? 1.0 : 1.0 + intensity
            let endScale: CGFloat = zoomIn ? 1.0 + intensity : 1.0
            let panRange = intensity * 80
            let startX = CGFloat.random(in: -panRange...panRange, using: &seed)
            let startY = CGFloat.random(in: -panRange...panRange, using: &seed)
            let endX = CGFloat.random(in: -panRange...panRange, using: &seed)
            let endY = CGFloat.random(in: -panRange...panRange, using: &seed)
            return KenBurns(
                startScale: startScale,
                endScale: endScale,
                startOffset: CGPoint(x: startX, y: startY),
                endOffset: CGPoint(x: endX, y: endY)
            )
        }
    }

    // MARK: - Drawing

    private func makePixelBuffer(pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }

    private func drawFrame(
        into buffer: CVPixelBuffer,
        outputSize: CGSize,
        primary: NSImage,
        primaryTransform: CGAffineTransform,
        primaryAlpha: CGFloat,
        secondary: NSImage?,
        secondaryTransform: CGAffineTransform?,
        secondaryAlpha: CGFloat
    ) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: baseAddress,
            width: Int(outputSize.width),
            height: Int(outputSize.height),
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        // Black background
        context.setFillColor(CGColor.black)
        context.fill(CGRect(origin: .zero, size: outputSize))

        if let secondary = secondary, let st = secondaryTransform, secondaryAlpha > 0.001 {
            drawImage(secondary, into: context, outputSize: outputSize, transform: st, alpha: secondaryAlpha)
        }

        drawImage(primary, into: context, outputSize: outputSize, transform: primaryTransform, alpha: primaryAlpha)
    }

    private func drawImage(
        _ image: NSImage,
        into context: CGContext,
        outputSize: CGSize,
        transform: CGAffineTransform,
        alpha: CGFloat
    ) {
        var rect = CGRect(origin: .zero, size: outputSize)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return }

        let imageAspect = CGFloat(cgImage.width) / CGFloat(cgImage.height)
        let outAspect = outputSize.width / outputSize.height

        // Cover-fit so the image fills the output rect.
        var coverSize = outputSize
        if imageAspect > outAspect {
            coverSize.width = outputSize.height * imageAspect
        } else {
            coverSize.height = outputSize.width / imageAspect
        }

        // Oversample so Ken Burns pan never exposes black edges around
        // the canvas border at minimum scale (1.0).
        coverSize.width *= coverPad
        coverSize.height *= coverPad

        let drawOrigin = CGPoint(
            x: (outputSize.width - coverSize.width) / 2,
            y: (outputSize.height - coverSize.height) / 2
        )

        context.saveGState()
        context.setAlpha(alpha)

        // Anchor the Ken Burns transform around the image center.
        context.translateBy(x: outputSize.width / 2, y: outputSize.height / 2)
        context.concatenate(transform)
        context.translateBy(x: -outputSize.width / 2, y: -outputSize.height / 2)

        context.draw(cgImage, in: CGRect(origin: drawOrigin, size: coverSize))
        context.restoreGState()
    }
}
