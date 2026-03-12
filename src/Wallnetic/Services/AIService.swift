import Foundation
import AppKit

/// Generation request parameters
struct GenerationRequest {
    let prompt: String
    let negativePrompt: String
    let style: AIStyle?
    let width: Int
    let height: Int
    let steps: Int
    let guidanceScale: Double

    init(
        prompt: String,
        negativePrompt: String = "",
        style: AIStyle? = nil,
        width: Int = 1920,
        height: Int = 1080,
        steps: Int = 28,
        guidanceScale: Double = 7.5
    ) {
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.style = style
        self.width = width
        self.height = height
        self.steps = steps
        self.guidanceScale = guidanceScale
    }

    /// Build full prompt with style
    var fullPrompt: String {
        if let style = style {
            return "\(style.prompt), \(prompt)"
        }
        return prompt
    }

    /// Build full negative prompt with style
    var fullNegativePrompt: String {
        if let style = style {
            return [style.negativePrompt, negativePrompt]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }
        return negativePrompt
    }
}

/// Generation result
struct GenerationResult {
    let imageURL: URL
    let localURL: URL?
    let prompt: String
    let provider: AIProvider
    let generatedAt: Date
}

/// Service for AI provider interactions
class AIService {
    static let shared = AIService()

    private init() {}

    // MARK: - Screen Resolution

    /// Get the main screen resolution for wallpaper generation
    static var screenResolution: (width: Int, height: Int) {
        if let screen = NSScreen.main {
            let scale = screen.backingScaleFactor
            let width = Int(screen.frame.width * scale)
            let height = Int(screen.frame.height * scale)
            // Round to nearest 64 for AI model compatibility
            return (
                width: (width / 64) * 64,
                height: (height / 64) * 64
            )
        }
        return (1920, 1080)
    }

    // MARK: - Text-to-Image Generation

    /// Generate an image from text prompt
    func generateImage(
        request: GenerationRequest,
        provider: AIProvider,
        progressHandler: ((Double, String) -> Void)? = nil
    ) async throws -> GenerationResult {
        // Get API key
        guard let apiKey = KeychainManager.shared.getAPIKey(for: provider) else {
            throw AIServiceError.invalidAPIKey
        }

        switch provider {
        case .replicate:
            return try await generateWithReplicate(request: request, apiKey: apiKey, progressHandler: progressHandler)
        case .falai:
            return try await generateWithFalAI(request: request, apiKey: apiKey, progressHandler: progressHandler)
        }
    }

    // MARK: - Replicate Generation

    private func generateWithReplicate(
        request: GenerationRequest,
        apiKey: String,
        progressHandler: ((Double, String) -> Void)?
    ) async throws -> GenerationResult {
        progressHandler?(0.1, "Starting generation...")

        // Create prediction using FLUX model
        let createURL = URL(string: "https://api.replicate.com/v1/predictions")!

        var createRequest = URLRequest(url: createURL)
        createRequest.httpMethod = "POST"
        createRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "version": "black-forest-labs/flux-schnell",
            "input": [
                "prompt": request.fullPrompt,
                "num_outputs": 1,
                "aspect_ratio": aspectRatioString(width: request.width, height: request.height),
                "output_format": "png",
                "output_quality": 90
            ]
        ]
        createRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        progressHandler?(0.2, "Sending request to Replicate...")

        let (createData, createResponse) = try await URLSession.shared.data(for: createRequest)

        guard let httpResponse = createResponse as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 201 || httpResponse.statusCode == 200 else {
            throw AIServiceError.serverError(httpResponse.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: createData) as? [String: Any],
              let predictionId = json["id"] as? String else {
            throw AIServiceError.invalidResponse
        }

        progressHandler?(0.3, "Generation started...")

        // Poll for completion
        let pollURL = URL(string: "https://api.replicate.com/v1/predictions/\(predictionId)")!
        var pollRequest = URLRequest(url: pollURL)
        pollRequest.httpMethod = "GET"
        pollRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var attempts = 0
        let maxAttempts = 60 // 2 minutes max

        while attempts < maxAttempts {
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            attempts += 1

            let progress = 0.3 + (Double(attempts) / Double(maxAttempts)) * 0.5
            progressHandler?(progress, "Generating... (\(attempts * 2)s)")

            let (pollData, _) = try await URLSession.shared.data(for: pollRequest)

            guard let pollJson = try JSONSerialization.jsonObject(with: pollData) as? [String: Any],
                  let status = pollJson["status"] as? String else {
                continue
            }

            switch status {
            case "succeeded":
                progressHandler?(0.9, "Downloading image...")
                if let output = pollJson["output"] as? [String],
                   let imageURLString = output.first,
                   let imageURL = URL(string: imageURLString) {
                    let localURL = try await downloadImage(from: imageURL)
                    progressHandler?(1.0, "Complete!")
                    return GenerationResult(
                        imageURL: imageURL,
                        localURL: localURL,
                        prompt: request.fullPrompt,
                        provider: .replicate,
                        generatedAt: Date()
                    )
                }
                throw AIServiceError.invalidResponse

            case "failed", "canceled":
                let error = pollJson["error"] as? String ?? "Generation failed"
                throw AIServiceError.generationFailed(error)

            default:
                continue
            }
        }

        throw AIServiceError.timeout
    }

    // MARK: - fal.ai Generation

    private func generateWithFalAI(
        request: GenerationRequest,
        apiKey: String,
        progressHandler: ((Double, String) -> Void)?
    ) async throws -> GenerationResult {
        progressHandler?(0.1, "Starting generation...")

        let url = URL(string: "https://fal.run/fal-ai/flux/schnell")!

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 120

        let body: [String: Any] = [
            "prompt": request.fullPrompt,
            "image_size": [
                "width": request.width,
                "height": request.height
            ],
            "num_inference_steps": request.steps,
            "num_images": 1,
            "enable_safety_checker": false
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        progressHandler?(0.3, "Generating with fal.ai...")

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorJson["detail"] as? String {
                throw AIServiceError.generationFailed(detail)
            }
            throw AIServiceError.serverError(httpResponse.statusCode)
        }

        progressHandler?(0.8, "Processing response...")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let images = json["images"] as? [[String: Any]],
              let firstImage = images.first,
              let imageURLString = firstImage["url"] as? String,
              let imageURL = URL(string: imageURLString) else {
            throw AIServiceError.invalidResponse
        }

        progressHandler?(0.9, "Downloading image...")
        let localURL = try await downloadImage(from: imageURL)

        progressHandler?(1.0, "Complete!")

        return GenerationResult(
            imageURL: imageURL,
            localURL: localURL,
            prompt: request.fullPrompt,
            provider: .falai,
            generatedAt: Date()
        )
    }

    // MARK: - Helpers

    private func aspectRatioString(width: Int, height: Int) -> String {
        let ratio = Double(width) / Double(height)
        if abs(ratio - 16.0/9.0) < 0.1 { return "16:9" }
        if abs(ratio - 9.0/16.0) < 0.1 { return "9:16" }
        if abs(ratio - 4.0/3.0) < 0.1 { return "4:3" }
        if abs(ratio - 3.0/4.0) < 0.1 { return "3:4" }
        if abs(ratio - 1.0) < 0.1 { return "1:1" }
        if abs(ratio - 21.0/9.0) < 0.1 { return "21:9" }
        return "16:9" // Default
    }

    private func downloadImage(from url: URL) async throws -> URL {
        let (data, _) = try await URLSession.shared.data(from: url)

        // Save to temporary location
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "wallnetic_generated_\(UUID().uuidString).png"
        let localURL = tempDir.appendingPathComponent(filename)

        try data.write(to: localURL)
        return localURL
    }

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
    case generationFailed(String)
    case timeout
    case noAPIKey

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .invalidAPIKey:
            return "Invalid API key - please check your API key in Settings"
        case .rateLimited:
            return "Rate limited - please try again later"
        case .serverError(let code):
            return "Server error (\(code))"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .generationFailed(let message):
            return "Generation failed: \(message)"
        case .timeout:
            return "Generation timed out - please try again"
        case .noAPIKey:
            return "No API key configured - please add your API key in Settings"
        }
    }
}
