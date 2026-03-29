import Foundation

/// Pexels Video API integration for free wallpaper discovery
class PexelsService {
    static let shared = PexelsService()

    private let baseURL = "https://api.pexels.com/videos"

    struct VideoResult: Identifiable, Codable {
        let id: Int
        let url: String
        let image: String
        let duration: Int
        let user: User
        let videoFiles: [VideoFile]
        let videoPictures: [VideoPicture]

        enum CodingKeys: String, CodingKey {
            case id, url, image, duration, user
            case videoFiles = "video_files"
            case videoPictures = "video_pictures"
        }

        struct User: Codable {
            let name: String
            let url: String
        }

        struct VideoFile: Codable {
            let id: Int
            let quality: String
            let fileType: String
            let width: Int?
            let height: Int?
            let link: String

            enum CodingKeys: String, CodingKey {
                case id, quality, width, height, link
                case fileType = "file_type"
            }
        }

        struct VideoPicture: Codable {
            let id: Int
            let picture: String
        }

        var bestFile: VideoFile? {
            videoFiles
                .filter { $0.quality == "hd" || $0.quality == "sd" }
                .sorted { ($0.width ?? 0) > ($1.width ?? 0) }
                .first
        }

        var resolution: String {
            guard let f = bestFile, let w = f.width, let h = f.height else { return "Unknown" }
            return "\(w)x\(h)"
        }

        var formattedDuration: String {
            let m = duration / 60
            let s = duration % 60
            return String(format: "%d:%02d", m, s)
        }
    }

    struct SearchResponse: Codable {
        let page: Int
        let perPage: Int
        let totalResults: Int
        let videos: [VideoResult]

        enum CodingKeys: String, CodingKey {
            case page, videos
            case perPage = "per_page"
            case totalResults = "total_results"
        }
    }

    private init() {}

    /// Search videos on Pexels
    func search(query: String, page: Int = 1, perPage: Int = 20) async throws -> SearchResponse {
        guard let apiKey = KeychainManager.shared.getAPIKey(for: .pexels) else {
            throw SourceError.noAPIKey("Pexels")
        }

        var components = URLComponents(string: "\(baseURL)/search")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)"),
            URLQueryItem(name: "orientation", value: "landscape"),
            URLQueryItem(name: "size", value: "large")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(SearchResponse.self, from: data)
    }

    /// Get popular videos
    func popular(page: Int = 1) async throws -> SearchResponse {
        guard let apiKey = KeychainManager.shared.getAPIKey(for: .pexels) else {
            throw SourceError.noAPIKey("Pexels")
        }

        var components = URLComponents(string: "\(baseURL)/popular")!
        components.queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "20"),
            URLQueryItem(name: "min_width", value: "1920")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(SearchResponse.self, from: data)
    }
}
