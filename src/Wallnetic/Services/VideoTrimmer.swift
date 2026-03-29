import Foundation
import AVFoundation
import AppKit

/// Trims video files to a specified time range
class VideoTrimmer {
    static let shared = VideoTrimmer()

    private init() {}

    /// Trims a video to the specified time range
    func trimVideo(
        source: URL,
        startTime: Double,
        endTime: Double,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> URL {
        let asset = AVURLAsset(url: source)

        guard try await asset.load(.isExportable) else {
            throw TrimError.notExportable
        }

        let duration = try await asset.load(.duration).seconds
        guard startTime >= 0, endTime <= duration, startTime < endTime else {
            throw TrimError.invalidRange
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw TrimError.exportFailed("Could not create export session")
        }

        let startCMTime = CMTime(seconds: startTime, preferredTimescale: 600)
        let endCMTime = CMTime(seconds: endTime, preferredTimescale: 600)
        exportSession.timeRange = CMTimeRange(start: startCMTime, end: endCMTime)
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4

        progressHandler?(0.1)

        // Monitor progress
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            progressHandler?(Double(exportSession.progress))
        }

        await exportSession.export()
        progressTimer.invalidate()

        guard exportSession.status == .completed else {
            throw TrimError.exportFailed(exportSession.error?.localizedDescription ?? "Unknown error")
        }

        progressHandler?(1.0)
        return outputURL
    }

    /// Generates frame thumbnails for a timeline view
    func generateTimelineThumbnails(
        for url: URL,
        count: Int = 10,
        height: CGFloat = 40
    ) async -> [NSImage] {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: height * 16 / 9, height: height)

        guard let duration = try? await asset.load(.duration).seconds, duration > 0 else {
            return []
        }

        var thumbnails: [NSImage] = []
        let interval = duration / Double(count)

        for i in 0..<count {
            let time = CMTime(seconds: interval * Double(i), preferredTimescale: 600)
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                thumbnails.append(NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
            }
        }

        return thumbnails
    }
}

// MARK: - Errors

enum TrimError: LocalizedError {
    case notExportable
    case invalidRange
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .notExportable: return "Video cannot be exported"
        case .invalidRange: return "Invalid time range"
        case .exportFailed(let msg): return "Export failed: \(msg)"
        }
    }
}
