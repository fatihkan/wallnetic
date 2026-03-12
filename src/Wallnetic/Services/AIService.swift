import Foundation
import AppKit

/// Video generation request parameters
struct VideoGenerationRequest {
    let prompt: String
    let negativePrompt: String
    let model: VideoModel
    let duration: Int  // seconds (5 or 10)
    let aspectRatio: String  // "16:9", "9:16", "1:1"
    let sourceImage: NSImage?  // For image-to-video

    init(
        prompt: String,
        negativePrompt: String = "",
        model: VideoModel = .klingStandard,
        duration: Int = 5,
        aspectRatio: String = "16:9",
        sourceImage: NSImage? = nil
    ) {
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.model = model
        self.duration = min(duration, model.maxDuration)
        self.aspectRatio = aspectRatio
        self.sourceImage = sourceImage
    }

    /// Whether this is an image-to-video request
    var isImg2Vid: Bool {
        sourceImage != nil
    }

    /// Estimated cost for this generation
    var estimatedCost: Double {
        return model.costPerSecond * Double(duration)
    }
}

/// Video generation result
struct VideoGenerationResult {
    let videoURL: URL
    let localURL: URL
    let prompt: String
    let model: VideoModel
    let duration: Int
    let generatedAt: Date
}

/// Service for video AI generation via fal.ai
class AIService {
    static let shared = AIService()

    private let baseURL = "https://queue.fal.run"
    private let statusBaseURL = "https://queue.fal.run"

    private init() {}

    // MARK: - Video Generation

    /// Generate a video from text or image
    func generateVideo(
        request: VideoGenerationRequest,
        progressHandler: ((Double, String) -> Void)? = nil
    ) async throws -> VideoGenerationResult {
        // Get API key
        guard let apiKey = KeychainManager.shared.getAPIKey(for: .falai) else {
            throw AIServiceError.noAPIKey
        }

        progressHandler?(0.05, "Preparing request...")

        // Build request
        let endpoint = request.isImg2Vid ? request.model.falImg2VidEndpoint : request.model.falEndpoint
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else {
            throw AIServiceError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 30

        // Build body based on model
        let body = try buildRequestBody(for: request)
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        progressHandler?(0.1, "Submitting to \(request.model.displayName)...")

        // Submit request
        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        // Handle non-2xx responses
        if httpResponse.statusCode >= 400 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorJson["detail"] as? String {
                throw AIServiceError.generationFailed(detail)
            }
            throw AIServiceError.serverError(httpResponse.statusCode)
        }

        // Parse queue response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let requestId = json["request_id"] as? String else {
            print("[AIService] Failed to parse queue response: \(String(data: data, encoding: .utf8) ?? "nil")")
            throw AIServiceError.invalidResponse
        }

        let statusURL = json["status_url"] as? String
        let responseURL = json["response_url"] as? String

        progressHandler?(0.2, "Queued, waiting for processing...")

        // Poll for completion
        let result = try await pollForCompletion(
            requestId: requestId,
            statusURL: statusURL,
            responseURL: responseURL,
            apiKey: apiKey,
            request: request,
            progressHandler: progressHandler
        )

        return result
    }

    // MARK: - Request Body Builders

    private func buildRequestBody(for request: VideoGenerationRequest) throws -> [String: Any] {
        var body: [String: Any] = [:]

        switch request.model {
        case .klingStandard, .klingPro:
            body = buildKlingBody(for: request)
        case .minimax:
            body = buildMinimaxBody(for: request)
        case .lumaRay:
            body = buildLumaBody(for: request)
        case .runway:
            body = buildRunwayBody(for: request)
        case .pika:
            body = buildPikaBody(for: request)
        case .wan:
            body = buildWanBody(for: request)
        }

        // Add source image if present
        if let sourceImage = request.sourceImage {
            if let imageDataURL = imageToBase64DataURL(sourceImage) {
                body["image_url"] = imageDataURL
            }
        }

        return body
    }

    private func buildKlingBody(for request: VideoGenerationRequest) -> [String: Any] {
        return [
            "prompt": request.prompt,
            "negative_prompt": request.negativePrompt,
            "duration": request.duration <= 5 ? "5" : "10",
            "aspect_ratio": request.aspectRatio
        ]
    }

    private func buildMinimaxBody(for request: VideoGenerationRequest) -> [String: Any] {
        return [
            "prompt": request.prompt,
            "prompt_optimizer": true
        ]
    }

    private func buildLumaBody(for request: VideoGenerationRequest) -> [String: Any] {
        return [
            "prompt": request.prompt,
            "aspect_ratio": request.aspectRatio,
            "loop": true  // Enable looping for wallpapers
        ]
    }

    private func buildRunwayBody(for request: VideoGenerationRequest) -> [String: Any] {
        return [
            "prompt": request.prompt,
            "duration": request.duration <= 5 ? 5 : 10,
            "aspect_ratio": request.aspectRatio == "9:16" ? "9:16" : "16:9"
        ]
    }

    private func buildPikaBody(for request: VideoGenerationRequest) -> [String: Any] {
        return [
            "prompt": request.prompt,
            "negative_prompt": request.negativePrompt,
            "style": "anime",  // Default to anime style
            "aspect_ratio": request.aspectRatio
        ]
    }

    private func buildWanBody(for request: VideoGenerationRequest) -> [String: Any] {
        // Calculate resolution from aspect ratio
        let resolution: [String: Int]
        switch request.aspectRatio {
        case "9:16":
            resolution = ["width": 480, "height": 832]
        case "1:1":
            resolution = ["width": 640, "height": 640]
        default: // 16:9
            resolution = ["width": 832, "height": 480]
        }

        return [
            "prompt": request.prompt,
            "negative_prompt": request.negativePrompt,
            "resolution": resolution,
            "num_frames": request.duration <= 5 ? 81 : 161  // ~5s or ~10s at 16fps
        ]
    }

    // MARK: - Polling

    private func pollForCompletion(
        requestId: String,
        statusURL: String?,
        responseURL: String?,
        apiKey: String,
        request: VideoGenerationRequest,
        progressHandler: ((Double, String) -> Void)?
    ) async throws -> VideoGenerationResult {
        let maxAttempts = 120  // 4 minutes max (2s intervals)
        var attempts = 0

        // Use status URL or construct one
        let pollURL: URL
        if let statusURL = statusURL, let url = URL(string: statusURL) {
            pollURL = url
        } else {
            pollURL = URL(string: "\(statusBaseURL)/\(request.model.falEndpoint)/requests/\(requestId)/status")!
        }

        while attempts < maxAttempts {
            try await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds
            attempts += 1

            // Calculate progress (20% to 90% during polling)
            let progress = 0.2 + (Double(attempts) / Double(maxAttempts)) * 0.7
            progressHandler?(min(progress, 0.9), "Generating video... (\(attempts * 2)s)")

            // Create status request
            var statusRequest = URLRequest(url: pollURL)
            statusRequest.httpMethod = "GET"
            statusRequest.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
            statusRequest.timeoutInterval = 10

            let (data, _) = try await URLSession.shared.data(for: statusRequest)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String else {
                continue
            }

            switch status.uppercased() {
            case "COMPLETED":
                progressHandler?(0.95, "Downloading video...")

                // Get response URL
                let resultURL: URL
                if let responseURL = responseURL, let url = URL(string: responseURL) {
                    resultURL = url
                } else if let respURL = json["response_url"] as? String, let url = URL(string: respURL) {
                    resultURL = url
                } else {
                    // Try to get video directly from response
                    if let video = json["video"] as? [String: Any],
                       let videoURLString = video["url"] as? String,
                       let videoURL = URL(string: videoURLString) {
                        let localURL = try await downloadVideo(from: videoURL)
                        progressHandler?(1.0, "Complete!")
                        return VideoGenerationResult(
                            videoURL: videoURL,
                            localURL: localURL,
                            prompt: request.prompt,
                            model: request.model,
                            duration: request.duration,
                            generatedAt: Date()
                        )
                    }
                    throw AIServiceError.invalidResponse
                }

                // Fetch the full response
                var resultRequest = URLRequest(url: resultURL)
                resultRequest.httpMethod = "GET"
                resultRequest.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")

                let (resultData, _) = try await URLSession.shared.data(for: resultRequest)

                guard let resultJson = try JSONSerialization.jsonObject(with: resultData) as? [String: Any] else {
                    throw AIServiceError.invalidResponse
                }

                // Extract video URL (different models have different response formats)
                let videoURL = try extractVideoURL(from: resultJson, model: request.model)
                let localURL = try await downloadVideo(from: videoURL)

                progressHandler?(1.0, "Complete!")

                return VideoGenerationResult(
                    videoURL: videoURL,
                    localURL: localURL,
                    prompt: request.prompt,
                    model: request.model,
                    duration: request.duration,
                    generatedAt: Date()
                )

            case "FAILED":
                let error = json["error"] as? String ?? "Generation failed"
                throw AIServiceError.generationFailed(error)

            case "IN_QUEUE", "IN_PROGRESS":
                // Get queue position if available
                if let logs = json["logs"] as? [[String: Any]], let lastLog = logs.last,
                   let message = lastLog["message"] as? String {
                    progressHandler?(min(progress, 0.9), message)
                }
                continue

            default:
                continue
            }
        }

        throw AIServiceError.timeout
    }

    // MARK: - Response Parsing

    private func extractVideoURL(from json: [String: Any], model: VideoModel) throws -> URL {
        // Try common response formats
        if let video = json["video"] as? [String: Any],
           let urlString = video["url"] as? String,
           let url = URL(string: urlString) {
            return url
        }

        if let urlString = json["video_url"] as? String,
           let url = URL(string: urlString) {
            return url
        }

        if let videos = json["videos"] as? [[String: Any]],
           let first = videos.first,
           let urlString = first["url"] as? String,
           let url = URL(string: urlString) {
            return url
        }

        if let output = json["output"] as? [String: Any],
           let urlString = output["video_url"] as? String,
           let url = URL(string: urlString) {
            return url
        }

        // Log for debugging
        print("[AIService] Unknown response format. Keys: \(json.keys)")
        throw AIServiceError.invalidResponse
    }

    // MARK: - Download

    private func downloadVideo(from url: URL) async throws -> URL {
        let (data, _) = try await URLSession.shared.data(from: url)

        // Save to Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let wallneticDir = appSupport.appendingPathComponent("Wallnetic/Generated")

        try FileManager.default.createDirectory(at: wallneticDir, withIntermediateDirectories: true)

        let filename = "video_\(UUID().uuidString).mp4"
        let localURL = wallneticDir.appendingPathComponent(filename)

        try data.write(to: localURL)
        return localURL
    }

    // MARK: - Image Encoding

    private func imageToBase64DataURL(_ image: NSImage, maxSize: Int = 1024) -> String? {
        let resizedImage = resizeImage(image, maxSize: maxSize)

        guard let tiffData = resizedImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        let base64 = pngData.base64EncodedString()
        return "data:image/png;base64,\(base64)"
    }

    private func resizeImage(_ image: NSImage, maxSize: Int) -> NSImage {
        let width = image.size.width
        let height = image.size.height

        guard width > CGFloat(maxSize) || height > CGFloat(maxSize) else {
            return image
        }

        let ratio = min(CGFloat(maxSize) / width, CGFloat(maxSize) / height)
        let newSize = NSSize(width: width * ratio, height: height * ratio)

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()

        return newImage
    }

    // MARK: - API Key Validation

    func validateAPIKey(_ apiKey: String) async throws -> Bool {
        // Use a simple endpoint to verify the key
        guard let url = URL(string: "https://fal.run/fal-ai/flux/schnell") else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        // Minimal payload to test auth
        let body: [String: Any] = [
            "prompt": "test",
            "num_inference_steps": 1,
            "num_images": 1,
            "image_size": ["width": 256, "height": 256]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200, 201, 202:
            return true
        case 401, 403:
            throw AIServiceError.invalidAPIKey
        case 422, 400:
            // Auth succeeded but validation error - key is valid
            return true
        case 429:
            throw AIServiceError.rateLimited
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
            return "No API key configured - please add your fal.ai API key in Settings"
        }
    }
}
