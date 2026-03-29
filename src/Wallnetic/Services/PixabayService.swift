import Foundation

/// Pixabay Video API integration for free wallpaper discovery
class PixabayService {
    static let shared = PixabayService()

    private let baseURL = "https://pixabay.com/api/videos/"

    struct VideoResult: Identifiable, Codable {
        let id: Int
        let pageURL: String
        let tags: String
        let videos: Videos
        let user: String
        let userImageURL: String

        struct Videos: Codable {
            let large: VideoSize?
            let medium: VideoSize
            let small: VideoSize

            struct VideoSize: Codable {
                let url: String
                let width: Int
                let height: Int
                let size: Int
            }
        }

        var bestURL: String {
            videos.large?.url ?? videos.medium.url
        }

        var resolution: String {
            let v = videos.large ?? videos.medium
            return "\(v.width)x\(v.height)"
        }

        var fileSizeMB: String {
            let v = videos.large ?? videos.medium
            return String(format: "%.1f MB", Double(v.size) / 1_000_000)
        }
    }

    struct SearchResponse: Codable {
        let total: Int
        let totalHits: Int
        let hits: [VideoResult]
    }

    private init() {}

    /// Search videos on Pixabay
    func search(
        query: String,
        page: Int = 1,
        perPage: Int = 20,
        category: String? = nil
    ) async throws -> SearchResponse {
        guard let apiKey = KeychainManager.shared.getAPIKey(for: .pixabay) else {
            throw SourceError.noAPIKey("Pixabay")
        }

        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)"),
            URLQueryItem(name: "video_type", value: "animation"),
            URLQueryItem(name: "min_width", value: "1920"),
            URLQueryItem(name: "safesearch", value: "true")
        ]

        if let category = category {
            components.queryItems?.append(URLQueryItem(name: "category", value: category))
        }

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(SearchResponse.self, from: data)
    }

    /// Get popular videos
    func popular(page: Int = 1) async throws -> SearchResponse {
        guard let apiKey = KeychainManager.shared.getAPIKey(for: .pixabay) else {
            throw SourceError.noAPIKey("Pixabay")
        }

        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "20"),
            URLQueryItem(name: "order", value: "popular"),
            URLQueryItem(name: "min_width", value: "1920"),
            URLQueryItem(name: "safesearch", value: "true")
        ]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(SearchResponse.self, from: data)
    }
}
