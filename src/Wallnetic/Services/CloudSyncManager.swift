import Foundation

/// Syncs generation history to Supabase cloud
class CloudSyncManager: ObservableObject {
    static let shared = CloudSyncManager()

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?

    private init() {}

    // MARK: - Sync Generation to Cloud

    /// Saves a generation record to Supabase
    func syncGeneration(
        prompt: String,
        negativePrompt: String,
        model: String,
        duration: Int,
        aspectRatio: String,
        wasImg2Vid: Bool,
        cost: Double
    ) async {
        guard AuthManager.shared.isAuthenticated,
              let userId = AuthManager.shared.userId else { return }

        do {
            _ = try await SupabaseClient.shared.request(
                path: "/rest/v1/generations",
                method: "POST",
                body: [
                    "user_id": userId,
                    "prompt": prompt,
                    "negative_prompt": negativePrompt,
                    "model": model,
                    "duration": duration,
                    "aspect_ratio": aspectRatio,
                    "was_img2vid": wasImg2Vid,
                    "cost": cost
                ],
                headers: ["Prefer": "return=minimal"]
            )
            NSLog("[CloudSync] Generation synced")
        } catch {
            NSLog("[CloudSync] Sync error: %@", error.localizedDescription)
        }
    }

    // MARK: - Fetch Cloud History

    /// Fetches generation history from Supabase
    func fetchHistory() async -> [CloudGeneration] {
        guard AuthManager.shared.isAuthenticated else { return [] }

        do {
            let (data, _) = try await SupabaseClient.shared.request(
                path: "/rest/v1/generations?order=created_at.desc&limit=50",
                method: "GET"
            )

            let generations = try JSONDecoder().decode([CloudGeneration].self, from: data)
            await MainActor.run {
                lastSyncDate = Date()
                isSyncing = false
            }
            return generations
        } catch {
            NSLog("[CloudSync] Fetch error: %@", error.localizedDescription)
            return []
        }
    }

    // MARK: - Full Sync

    func performSync() async {
        await MainActor.run { isSyncing = true }

        _ = await fetchHistory()

        await MainActor.run {
            isSyncing = false
            lastSyncDate = Date()
        }
    }
}

// MARK: - Cloud Generation Model

struct CloudGeneration: Codable, Identifiable {
    let id: String
    let prompt: String
    let negativePrompt: String?
    let model: String
    let duration: Int
    let aspectRatio: String
    let wasImg2vid: Bool?
    let videoUrl: String?
    let thumbnailUrl: String?
    let cost: Double?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, prompt, model, duration, cost
        case negativePrompt = "negative_prompt"
        case aspectRatio = "aspect_ratio"
        case wasImg2vid = "was_img2vid"
        case videoUrl = "video_url"
        case thumbnailUrl = "thumbnail_url"
        case createdAt = "created_at"
    }
}
