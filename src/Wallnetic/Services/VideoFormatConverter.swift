import Foundation
import AVFoundation
import AppKit
import ImageIO

/// Converts non-native video formats (GIF, WebM) to MP4 for playback
class VideoFormatConverter {
    static let shared = VideoFormatConverter()

    /// Supported import formats (beyond native MP4/MOV)
    static let additionalFormats = ["gif", "webm", "webp"]
    static let allSupportedFormats = ["mp4", "mov", "m4v", "hevc", "gif", "webm", "webp"]

    private init() {}

    /// Checks if a file needs conversion before import
    func needsConversion(_ url: URL) -> Bool {
        Self.additionalFormats.contains(url.pathExtension.lowercased())
    }

    /// Converts a file to MP4 format
    /// Returns the URL of the converted file
    func convertToMP4(
        source: URL,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> URL {
        let ext = source.pathExtension.lowercased()

        switch ext {
        case "gif":
            return try await convertGIFToMP4(source: source, progressHandler: progressHandler)
        case "webm":
            return try await convertWebMToMP4(source: source, progressHandler: progressHandler)
        case "webp":
            return try await convertAnimatedWebPToMP4(source: source, progressHandler: progressHandler)
        default:
            throw ConversionError.unsupportedFormat(ext)
        }
    }

    // MARK: - GIF to MP4

    private func convertGIFToMP4(
        source: URL,
        progressHandler: ((Double) -> Void)?
    ) async throws -> URL {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            throw ConversionError.failedToRead
        }

        let frameCount = CGImageSourceGetCount(imageSource)
        guard frameCount > 0 else { throw ConversionError.noFrames }

        // Get first frame to determine size
        guard let firstImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw ConversionError.failedToRead
        }

        let width = CGFloat(firstImage.width)
        let height = CGFloat(firstImage.height)
        // Ensure even dimensions for H.264
        let evenWidth = Int(width) & ~1
        let evenHeight = Int(height) & ~1

        // Output URL
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        // Setup AVAssetWriter
        let writer = try AVAssetWriter(url: outputURL, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: evenWidth,
            AVVideoHeightKey: evenHeight
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: evenWidth,
                kCVPixelBufferHeightKey as String: evenHeight
            ]
        )

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Process frames
        let ciContext = CIContext()  // Reuse single CIContext (expensive to create)
        var frameTime = CMTime.zero
        let maxWaitAttempts = 500  // 5 seconds max wait per frame

        for i in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, i, nil) else { continue }

            // Get frame duration from GIF properties
            let frameDuration = gifFrameDuration(at: i, source: imageSource)
            let duration = CMTime(seconds: frameDuration, preferredTimescale: 600)

            // Wait for input ready with timeout
            var waitCount = 0
            while !input.isReadyForMoreMediaData {
                waitCount += 1
                if waitCount > maxWaitAttempts {
                    throw ConversionError.writeFailed("Writer input timed out at frame \(i)")
                }
                if writer.status == .failed {
                    throw ConversionError.writeFailed(writer.error?.localizedDescription ?? "Writer failed")
                }
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }

            // Create pixel buffer
            if let pool = adaptor.pixelBufferPool {
                var pixelBuffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)

                if let buffer = pixelBuffer {
                    let ciImage = CIImage(cgImage: cgImage)
                    ciContext.render(ciImage, to: buffer)
                    adaptor.append(buffer, withPresentationTime: frameTime)
                }
            }

            frameTime = CMTimeAdd(frameTime, duration)
            progressHandler?(Double(i) / Double(frameCount))
        }

        input.markAsFinished()
        await writer.finishWriting()

        guard writer.status == .completed else {
            throw ConversionError.writeFailed(writer.error?.localizedDescription ?? "Unknown")
        }

        progressHandler?(1.0)
        return outputURL
    }

    private func gifFrameDuration(at index: Int, source: CGImageSource) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
              let gifProps = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] else {
            return 0.1
        }

        if let delay = gifProps[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double, delay > 0 {
            return delay
        }
        if let delay = gifProps[kCGImagePropertyGIFDelayTime as String] as? Double, delay > 0 {
            return delay
        }
        return 0.1
    }

    // MARK: - WebM to MP4 (requires system ffmpeg)

    private func convertWebMToMP4(
        source: URL,
        progressHandler: ((Double) -> Void)?
    ) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        // Try system ffmpeg
        let ffmpegPaths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        guard let ffmpegPath = ffmpegPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw ConversionError.ffmpegNotFound
        }

        progressHandler?(0.1)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-i", source.path,
            "-c:v", "libx264",
            "-preset", "fast",
            "-crf", "23",
            "-an",          // No audio
            "-y",           // Overwrite
            outputURL.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ConversionError.ffmpegFailed
        }

        progressHandler?(1.0)
        return outputURL
    }

    // MARK: - Animated WebP to MP4

    private func convertAnimatedWebPToMP4(
        source: URL,
        progressHandler: ((Double) -> Void)?
    ) async throws -> URL {
        // WebP can be handled same as GIF via ImageIO on macOS 12+
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            throw ConversionError.failedToRead
        }

        let frameCount = CGImageSourceGetCount(imageSource)
        if frameCount > 1 {
            // Animated WebP - use same approach as GIF
            return try await convertGIFToMP4(source: source, progressHandler: progressHandler)
        } else {
            throw ConversionError.notAnimated
        }
    }
}

// MARK: - Errors

enum ConversionError: LocalizedError {
    case unsupportedFormat(String)
    case failedToRead
    case noFrames
    case notAnimated
    case writeFailed(String)
    case ffmpegNotFound
    case ffmpegFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let fmt): return "Unsupported format: .\(fmt)"
        case .failedToRead: return "Failed to read source file"
        case .noFrames: return "No frames found in file"
        case .notAnimated: return "File is not animated"
        case .writeFailed(let msg): return "Write failed: \(msg)"
        case .ffmpegNotFound: return "WebM conversion requires ffmpeg. Install via: brew install ffmpeg"
        case .ffmpegFailed: return "ffmpeg conversion failed"
        }
    }
}
