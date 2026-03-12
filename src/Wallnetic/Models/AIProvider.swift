import Foundation

/// Supported AI providers for wallpaper generation
enum AIProvider: String, CaseIterable {
    case replicate = "replicate"
    case falai = "fal.ai"

    var displayName: String {
        switch self {
        case .replicate: return "Replicate"
        case .falai: return "fal.ai"
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .replicate: return "r8_xxxxxxxxxxxxxxxxxxxxxxxxxxxx"
        case .falai: return "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
        }
    }

    var signupURL: URL {
        switch self {
        case .replicate: return URL(string: "https://replicate.com/account/api-tokens")!
        case .falai: return URL(string: "https://fal.ai/dashboard/keys")!
        }
    }
}
