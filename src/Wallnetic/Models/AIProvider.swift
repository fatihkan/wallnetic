import Foundation

/// Supported video AI models for wallpaper generation
/// All models are accessed via fal.ai unified API
enum VideoModel: String, CaseIterable, Codable {
    case klingStandard = "kling-standard"
    case klingPro = "kling-pro"
    case minimax = "minimax-hailuo"
    case lumaRay = "luma-ray"
    case runway = "runway-gen3"
    case pika = "pika"
    case wan = "wan"

    var displayName: String {
        switch self {
        case .klingStandard: return "Kling Standard"
        case .klingPro: return "Kling Pro"
        case .minimax: return "Minimax Hailuo"
        case .lumaRay: return "Luma Ray"
        case .runway: return "Runway Gen-3"
        case .pika: return "Pika"
        case .wan: return "Wan 2.1"
        }
    }

    var description: String {
        switch self {
        case .klingStandard: return "Fast anime & stylized videos"
        case .klingPro: return "High quality anime & cinematic"
        case .minimax: return "Best for anime expressions"
        case .lumaRay: return "Realistic & smooth motion"
        case .runway: return "Cinematic quality videos"
        case .pika: return "Creative animations"
        case .wan: return "Budget-friendly option"
        }
    }

    var icon: String {
        switch self {
        case .klingStandard, .klingPro: return "sparkles.tv"
        case .minimax: return "face.smiling"
        case .lumaRay: return "camera.metering.multispot"
        case .runway: return "film"
        case .pika: return "wand.and.stars"
        case .wan: return "dollarsign.circle"
        }
    }

    /// fal.ai model endpoint
    var falEndpoint: String {
        switch self {
        case .klingStandard: return "fal-ai/kling-video/v1/standard/text-to-video"
        case .klingPro: return "fal-ai/kling-video/v1.5/pro/text-to-video"
        case .minimax: return "fal-ai/minimax-video/video-01/text-to-video"
        case .lumaRay: return "fal-ai/luma-dream-machine"
        case .runway: return "fal-ai/runway-gen3/turbo/text-to-video"
        case .pika: return "fal-ai/pika/v2/text-to-video"
        case .wan: return "fal-ai/wan/v2.1/text-to-video"
        }
    }

    /// fal.ai image-to-video endpoint
    var falImg2VidEndpoint: String {
        switch self {
        case .klingStandard: return "fal-ai/kling-video/v1/standard/image-to-video"
        case .klingPro: return "fal-ai/kling-video/v1.5/pro/image-to-video"
        case .minimax: return "fal-ai/minimax-video/video-01/image-to-video"
        case .lumaRay: return "fal-ai/luma-dream-machine/image-to-video"
        case .runway: return "fal-ai/runway-gen3/turbo/image-to-video"
        case .pika: return "fal-ai/pika/v2/image-to-video"
        case .wan: return "fal-ai/wan/v2.1/image-to-video"
        }
    }

    /// Estimated cost per second (USD)
    var costPerSecond: Double {
        switch self {
        case .klingStandard: return 0.07
        case .klingPro: return 0.15
        case .minimax: return 0.10
        case .lumaRay: return 0.12
        case .runway: return 0.15
        case .pika: return 0.10
        case .wan: return 0.05
        }
    }

    /// Maximum video duration in seconds
    var maxDuration: Int {
        switch self {
        case .klingStandard, .klingPro: return 10
        case .minimax: return 6
        case .lumaRay: return 9
        case .runway: return 10
        case .pika: return 5
        case .wan: return 5
        }
    }

    /// Supported aspect ratios
    var supportedAspectRatios: [String] {
        switch self {
        case .klingStandard, .klingPro:
            return ["16:9", "9:16", "1:1"]
        case .minimax:
            return ["16:9", "9:16", "1:1"]
        case .lumaRay:
            return ["16:9", "9:16", "1:1", "4:3", "3:4", "21:9"]
        case .runway:
            return ["16:9", "9:16"]
        case .pika:
            return ["16:9", "9:16", "1:1"]
        case .wan:
            return ["16:9", "9:16", "1:1"]
        }
    }

    /// Best for anime/stylized content
    var isAnimeOptimized: Bool {
        switch self {
        case .klingStandard, .klingPro, .minimax, .pika:
            return true
        case .lumaRay, .runway, .wan:
            return false
        }
    }
}

/// API Provider for authentication
enum APIProvider: String, CaseIterable {
    case falai = "fal.ai"
    case supabase = "supabase"
    case pixabay = "pixabay"
    case pexels = "pexels"

    var displayName: String {
        switch self {
        case .falai: return "fal.ai"
        case .supabase: return "Supabase"
        case .pixabay: return "Pixabay"
        case .pexels: return "Pexels"
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .falai: return "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
        case .supabase: return "session-token"
        case .pixabay: return "xxxxxxx-xxxxxxxxxxxxxxx"
        case .pexels: return "xxxxxxxxxxxxxxxxxxxxxxx"
        }
    }

    var signupURL: URL {
        switch self {
        case .falai: return URL(string: "https://fal.ai/dashboard/keys")!
        case .supabase: return URL(string: "https://supabase.com")!
        case .pixabay: return URL(string: "https://pixabay.com/api/docs/")!
        case .pexels: return URL(string: "https://www.pexels.com/api/")!
        }
    }
}

// MARK: - Legacy Support (kept for compatibility)

/// Legacy AIProvider - redirects to fal.ai
@available(*, deprecated, message: "Use APIProvider instead")
typealias AIProvider = APIProvider
