import Foundation
import SwiftUI

/// Manages the community wallpaper store/marketplace
class WallpaperStoreManager: ObservableObject {
    static let shared = WallpaperStoreManager()

    @Published var featuredWallpapers: [StoreWallpaper] = []
    @Published var categories: [StoreCategory] = StoreCategory.allCategories
    @Published var isLoading = false
    @Published var error: String?

    private init() {}

    // MARK: - Models

    struct StoreWallpaper: Identifiable, Codable {
        let id: String
        let name: String
        let author: String
        let category: String
        let previewURL: String
        let downloadURL: String
        let resolution: String
        let duration: String
        let fileSize: String
        let downloads: Int
        let rating: Double
        let isFree: Bool
    }

    struct StoreCategory: Identifiable {
        let id: String
        let name: String
        let icon: String
        let color: Color

        static let allCategories: [StoreCategory] = [
            StoreCategory(id: "nature", name: "Nature", icon: "leaf.fill", color: .green),
            StoreCategory(id: "abstract", name: "Abstract", icon: "circle.hexagongrid.fill", color: .purple),
            StoreCategory(id: "anime", name: "Anime", icon: "sparkles.tv.fill", color: .pink),
            StoreCategory(id: "space", name: "Space", icon: "moon.stars.fill", color: .indigo),
            StoreCategory(id: "city", name: "City", icon: "building.2.fill", color: .orange),
            StoreCategory(id: "ocean", name: "Ocean", icon: "water.waves", color: .blue),
            StoreCategory(id: "minimal", name: "Minimal", icon: "square.on.square", color: .gray),
            StoreCategory(id: "holiday", name: "Holiday", icon: "gift.fill", color: .red),
        ]
    }

    // MARK: - Fetch

    func fetchFeatured() async {
        await MainActor.run { isLoading = true }

        // In production, fetch from Supabase or API
        // Placeholder data for now
        await MainActor.run {
            featuredWallpapers = []
            isLoading = false
        }
    }

    func fetchCategory(_ categoryId: String) async -> [StoreWallpaper] {
        // In production, fetch from API
        return []
    }

    func searchWallpapers(query: String) async -> [StoreWallpaper] {
        // In production, search via API
        return []
    }

    // MARK: - Download

    func downloadWallpaper(_ wallpaper: StoreWallpaper) async throws {
        guard let url = URL(string: wallpaper.downloadURL) else {
            throw WallpaperStoreError.invalidURL
        }

        let downloadedURL = try await URLImporter.shared.downloadAndImport(from: url.absoluteString)
        _ = try await WallpaperManager.shared.importVideo(from: downloadedURL)

        // Cleanup temp file
        try? FileManager.default.removeItem(at: downloadedURL)

        Log.store.info("Downloaded: \(wallpaper.name, privacy: .public)")
    }
}

// MARK: - Errors

enum WallpaperStoreError: LocalizedError {
    case invalidURL
    case downloadFailed
    case notAvailable

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid download URL"
        case .downloadFailed: return "Download failed"
        case .notAvailable: return "Wallpaper Store coming soon"
        }
    }
}
