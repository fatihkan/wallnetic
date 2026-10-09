import AVFoundation

/// Resolution is a landscape/portrait bounding box; smaller sources are never enlarged.
enum VideoOptimizationPreset: String, CaseIterable, Identifiable, Codable {
    case compact, balanced, hevc
    var id: String { rawValue }
    var title: String {
        switch self {
        case .compact: return "Compact · H.264 · 720p · up to 15 fps"
        case .balanced: return "Balanced · H.264 · 1080p · up to 30 fps"
        case .hevc: return "HEVC · 1080p · up to 30 fps"
        }
    }
    var detail: String {
        switch self {
        case .compact: return "Lower resolution and fewer frames. Fine detail and motion smoothness may decrease."
        case .balanced: return "Keeps more detail and smoother motion, with broad playback compatibility."
        case .hevc: return "May create a smaller file, but encoding can take longer. Available when this Mac supports HEVC hardware encoding and decoding."
        }
    }
    var maxSize: CGSize { self == .compact ? CGSize(width: 1280, height: 720) : CGSize(width: 1920, height: 1080) }
    var fps: Double { self == .compact ? 15 : 30 }
    var exportPreset: String { self == .hevc ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality }
    var filenameLabel: String { self == .compact ? "H264-720p" : (self == .balanced ? "H264-1080p" : "HEVC-1080p") }
}

struct VideoOptimizationGeometry {
    let size: CGSize
    let transform: CGAffineTransform
    let frameDuration: CMTime

    static func make(size: CGSize, transform: CGAffineTransform, fps: Double, preset: VideoOptimizationPreset) throws -> Self {
        let values = [size.width, size.height, transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty]
        guard values.allSatisfy(\.isFinite), size.width >= 2, size.height >= 2,
              size.width <= 16384, size.height <= 16384,
              abs(transform.a * transform.d - transform.b * transform.c) > 0.0001 else {
            throw VideoOptimizationError.unsupported("The video dimensions or orientation are unsupported.")
        }
        let bounds = CGRect(origin: .zero, size: size).applying(transform).standardized
        guard bounds.width >= 2, bounds.height >= 2, bounds.width <= 32768, bounds.height <= 32768 else {
            throw VideoOptimizationError.unsupported("The video orientation is unsupported.")
        }
        let box = bounds.width >= bounds.height ? preset.maxSize : CGSize(width: preset.maxSize.height, height: preset.maxSize.width)
        let scale = min(1, min(box.width / bounds.width, box.height / bounds.height))
        let width = max(2, floor(bounds.width * scale / 2) * 2)
        let height = max(2, floor(bounds.height * scale / 2) * 2)
        let normalized = transform.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
        let fitted = normalized.concatenating(CGAffineTransform(scaleX: width / bounds.width, y: height / bounds.height))
        let targetFPS = fps.isFinite && fps > 0 ? min(fps, preset.fps) : preset.fps
        guard targetFPS >= 0.1 else { throw VideoOptimizationError.unsupported("The video frame rate is unsupported.") }
        return Self(size: CGSize(width: width, height: height), transform: fitted,
                    frameDuration: CMTime(seconds: 1 / targetFPS, preferredTimescale: 60000))
    }
}

struct VideoOptimizationInfo {
    let duration: Double
    let size: CGSize
    let frameRate: Double
    let sourceBytes: Int64
    let unavailable: [VideoOptimizationPreset: String]
    let assumesSDR: Bool
}

struct OptimizedVideoResult {
    let url: URL
    let sourceBytes: Int64
    let outputBytes: Int64
    let duration: Double
    let size: CGSize
    let frameRate: Double
}

enum VideoOptimizationError: LocalizedError {
    case unsupported(String), sourceChanged, busy, diskSpace(Int64), cannotCheckSpace, failed(String), invalidOutput
    var errorDescription: String? {
        switch self {
        case .unsupported(let reason): return reason
        case .sourceChanged: return "The source video is missing or changed. Refresh the library and try again."
        case .busy: return "Another video is being optimized. Wait for it to finish or cancel it first."
        case .diskSpace(let required): return "Not enough free disk space. Keep at least \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)) available and try again."
        case .cannotCheckSpace: return "Available disk space could not be checked. Check the library disk and try again."
        case .failed(let message): return "Could not create the optimized copy: \(message)"
        case .invalidOutput: return "The converted video failed verification. No copy was added; your original is unchanged."
        }
    }
}
