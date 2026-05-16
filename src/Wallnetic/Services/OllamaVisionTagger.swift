import Foundation
import AppKit

/// Local Ollama vision tagger (#116). Sends a base64-encoded thumbnail to a
/// vision-capable Ollama model (e.g. `llava`) running on `localhost:11434`
/// and parses the JSON `tags` array out of the streaming response.
///
/// **Optional feature.** If Ollama is not running, the request times out
/// quickly and the caller treats the wallpaper as "no auto-tags" — never a
/// hard failure.
///
/// Authoritative tags still live in `Wallpaper.tags` / `WallpaperMetadataStore.savedTags`;
/// this service just produces candidates and lets the caller apply them.
final class OllamaVisionTagger {
    /// Defaults — overridable via the OllamaConfig struct passed at call time.
    static let defaultEndpoint = URL(string: "http://localhost:11434/api/generate")!
    static let defaultModel = "llava"
    static let defaultPrompt = """
    Analyze this wallpaper. Reply with ONLY a JSON object in this exact shape:
    {"tags": ["tag1", "tag2", "tag3"]}
    Rules:
    - 3 to 6 tags
    - Each tag is one or two lowercase English words (e.g. "nature", "neon city", "anime")
    - No commentary, no markdown, no explanation. Just the JSON.
    """

    struct Config {
        let endpoint: URL
        let model: String
        let prompt: String
        let timeout: TimeInterval

        init(
            endpoint: URL = OllamaVisionTagger.defaultEndpoint,
            model: String = OllamaVisionTagger.defaultModel,
            prompt: String = OllamaVisionTagger.defaultPrompt,
            timeout: TimeInterval = 30
        ) {
            self.endpoint = endpoint
            self.model = model
            self.prompt = prompt
            self.timeout = timeout
        }
    }

    enum TaggerError: Error, Equatable {
        case ollamaUnreachable
        case badStatus(Int)
        case decodeFailed
        case malformedResponse
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    /// Generates tags for a single wallpaper. Resolves to an empty array if
    /// Ollama is offline — distinguishable from "tagged with 0 results"
    /// because this method returns `nil` for the offline case.
    func tags(for image: NSImage, config: Config = Config()) async -> [String]? {
        guard let base64 = base64Encode(image: image, maxDimension: 512) else {
            Log.ollama.debug("Skipping — could not encode thumbnail to JPEG.")
            return nil
        }

        let body: [String: Any] = [
            "model": config.model,
            "prompt": config.prompt,
            "images": [base64],
            "stream": false
        ]

        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = config.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            Log.ollama.error("Request body encoding failed: \(String(describing: error), privacy: .public)")
            return nil
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                Log.ollama.error("Non-HTTP response from Ollama.")
                return nil
            }
            guard (200..<300).contains(http.statusCode) else {
                Log.ollama.error("Ollama returned status \(http.statusCode, privacy: .public)")
                return nil
            }
            return Self.parseTags(fromResponseData: data)
        } catch let urlError as URLError where urlError.code == .cannotConnectToHost
                                              || urlError.code == .timedOut
                                              || urlError.code == .notConnectedToInternet {
            // Expected when Ollama is not running locally — debug only.
            Log.ollama.debug("Ollama not reachable: \(urlError.localizedDescription, privacy: .public)")
            return nil
        } catch {
            Log.ollama.error("Ollama request failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: - Parser (pure, testable)

    /// Parses the `response` field of an Ollama `/api/generate` reply and
    /// extracts the JSON `tags` array. Tolerant: handles markdown code
    /// fences and trailing prose around the JSON.
    static func parseTags(fromResponseData data: Data) -> [String]? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = json["response"] as? String
        else {
            Log.ollama.error("Ollama reply was not valid JSON or missing 'response' field.")
            return nil
        }
        return parseTags(fromText: text)
    }

    /// Extracts the `tags` array from free-form model text. Returns nil if
    /// nothing JSON-looking is found.
    static func parseTags(fromText text: String) -> [String]? {
        // Find the first '{' and last '}' to tolerate prose / markdown
        // fences around the JSON.
        guard
            let start = text.firstIndex(of: "{"),
            let end = text.lastIndex(of: "}"),
            start <= end
        else { return nil }

        let slice = String(text[start...end])
        guard let payload = slice.data(using: .utf8) else { return nil }

        guard
            let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
            let raw = obj["tags"] as? [Any]
        else { return nil }

        let cleaned: [String] = raw.compactMap { value in
            let s: String
            if let str = value as? String { s = str }
            else { s = String(describing: value) }
            return cleanTag(s)
        }
        return cleaned.isEmpty ? nil : Array(Set(cleaned)).sorted()
    }

    static func cleanTag(_ raw: String) -> String? {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'.,;:#"))
            .lowercased()
        guard !trimmed.isEmpty, trimmed.count <= 32 else { return nil }
        return trimmed
    }

    // MARK: - Image Encoding

    private func base64Encode(image: NSImage, maxDimension: CGFloat) -> String? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }

        // Downscale for bandwidth — vision models do not need full-res.
        let originalSize = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        let scale = min(1, maxDimension / max(originalSize.width, originalSize.height))
        let targetSize = NSSize(width: originalSize.width * scale, height: originalSize.height * scale)

        let scaled = NSImage(size: targetSize)
        scaled.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        scaled.unlockFocus()

        guard
            let scaledTiff = scaled.tiffRepresentation,
            let scaledRep = NSBitmapImageRep(data: scaledTiff),
            let jpeg = scaledRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        else { return nil }

        return jpeg.base64EncodedString()
    }
}
