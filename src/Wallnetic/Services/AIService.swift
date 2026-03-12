import Foundation

/// Service for AI provider interactions
class AIService {
    static let shared = AIService()

    private init() {}

    // MARK: - API Key Validation

    /// Validates an API key for the specified provider
    func validateAPIKey(_ apiKey: String, provider: AIProvider) async throws -> Bool {
        switch provider {
        case .replicate:
            return try await validateReplicateAPIKey(apiKey)
        case .falai:
            return try await validateFalAIKey(apiKey)
        }
    }

    // MARK: - Replicate Validation

    private func validateReplicateAPIKey(_ apiKey: String) async throws -> Bool {
        // Replicate API: GET /v1/account to verify token
        guard let url = URL(string: "https://api.replicate.com/v1/account") else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return true
        case 401:
            throw AIServiceError.invalidAPIKey
        case 429:
            throw AIServiceError.rateLimited
        default:
            throw AIServiceError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - fal.ai Validation

    private func validateFalAIKey(_ apiKey: String) async throws -> Bool {
        // fal.ai: Use a simple endpoint to verify the key
        guard let url = URL(string: "https://fal.run/fal-ai/flux/dev") else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        // Send minimal payload to check auth
        let body: [String: Any] = [
            "prompt": "test",
            "num_inference_steps": 1,
            "image_size": "square_hd"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200, 201, 202:
            // Success or queued - API key is valid
            return true
        case 401, 403:
            throw AIServiceError.invalidAPIKey
        case 429:
            throw AIServiceError.rateLimited
        case 400:
            // Bad request but auth succeeded - key is valid
            return true
        default:
            throw AIServiceError.serverError(httpResponse.statusCode)
        }
    }
}

// MARK: - Errors

enum AIServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidAPIKey
    case rateLimited
    case serverError(Int)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .invalidAPIKey:
            return "Invalid API key"
        case .rateLimited:
            return "Rate limited - please try again later"
        case .serverError(let code):
            return "Server error (\(code))"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
