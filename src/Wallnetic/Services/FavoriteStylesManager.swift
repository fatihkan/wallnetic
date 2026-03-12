import Foundation
import SwiftUI

/// Manager for favorite AI styles
class FavoriteStylesManager: ObservableObject {
    static let shared = FavoriteStylesManager()

    @Published private(set) var favoriteStyleIds: Set<String> = []

    private let defaults = UserDefaults.standard
    private let favoritesKey = "favoriteStyles"

    private init() {
        loadFavorites()
    }

    // MARK: - Public Methods

    /// Check if a style is favorited
    func isFavorite(_ style: AIStyle) -> Bool {
        favoriteStyleIds.contains(style.id)
    }

    /// Toggle favorite status for a style
    func toggleFavorite(_ style: AIStyle) {
        if favoriteStyleIds.contains(style.id) {
            favoriteStyleIds.remove(style.id)
        } else {
            favoriteStyleIds.insert(style.id)
        }
        saveFavorites()
    }

    /// Add a style to favorites
    func addFavorite(_ style: AIStyle) {
        favoriteStyleIds.insert(style.id)
        saveFavorites()
    }

    /// Remove a style from favorites
    func removeFavorite(_ style: AIStyle) {
        favoriteStyleIds.remove(style.id)
        saveFavorites()
    }

    /// Get all favorite styles
    var favoriteStyles: [AIStyle] {
        AIStyle.allStyles.filter { favoriteStyleIds.contains($0.id) }
    }

    // MARK: - Persistence

    private func loadFavorites() {
        if let savedIds = defaults.stringArray(forKey: favoritesKey) {
            favoriteStyleIds = Set(savedIds)
        }
    }

    private func saveFavorites() {
        defaults.set(Array(favoriteStyleIds), forKey: favoritesKey)
    }
}
