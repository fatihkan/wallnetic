import Foundation
import AppKit
import Combine

/// Orchestrates Ollama Vision auto-tagging across the wallpaper library
/// (#116). Exposes progress + cancellation so the Settings UI can show a
/// status indicator.
///
/// All requests are sequential — vision inference is GPU-bound on the local
/// Ollama process; firing them concurrently would just queue inside Ollama.
@MainActor
final class OllamaTaggingService: ObservableObject {
    static let shared = OllamaTaggingService()

    @Published private(set) var isRunning = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var statusText: String = ""
    @Published private(set) var lastError: String?

    @AppStorageKeyed("ollama.endpoint")
    var endpointString: String = "http://localhost:11434/api/generate"

    @AppStorageKeyed("ollama.model")
    var modelName: String = OllamaVisionTagger.defaultModel

    private let tagger: OllamaVisionTagger
    private var task: Task<Void, Never>?

    init(tagger: OllamaVisionTagger = OllamaVisionTagger()) {
        self.tagger = tagger
    }

    var configuredEndpoint: URL {
        URL(string: endpointString) ?? OllamaVisionTagger.defaultEndpoint
    }

    var config: OllamaVisionTagger.Config {
        OllamaVisionTagger.Config(
            endpoint: configuredEndpoint,
            model: modelName.isEmpty ? OllamaVisionTagger.defaultModel : modelName
        )
    }

    // MARK: - Batch Tagging

    /// Tags every wallpaper that has no existing tags. Existing tags are
    /// preserved — auto-tags only fill in the gap.
    func tagAll(wallpapers: [Wallpaper], manager: WallpaperManager) {
        guard !isRunning else { return }
        let untagged = wallpapers.filter { $0.tags.isEmpty }
        guard !untagged.isEmpty else {
            statusText = "All wallpapers already tagged."
            return
        }

        isRunning = true
        progress = 0
        lastError = nil
        statusText = "Preparing…"

        let cfg = config
        task = Task { [weak self] in
            guard let self else { return }
            let total = Double(untagged.count)
            var done: Double = 0

            for wallpaper in untagged {
                if Task.isCancelled { break }
                self.statusText = "Tagging \(wallpaper.displayName)…"

                let thumb = await wallpaper.generateThumbnail(size: CGSize(width: 512, height: 288))
                guard let thumb else {
                    done += 1
                    self.progress = done / total
                    continue
                }

                let tags = await self.tagger.tags(for: thumb, config: cfg)
                if let tags, !tags.isEmpty {
                    for tag in tags {
                        manager.addTag(tag, to: wallpaper)
                    }
                } else if tags == nil && done == 0 {
                    self.lastError = "Could not reach Ollama at \(cfg.endpoint.absoluteString)."
                    break
                }

                done += 1
                self.progress = done / total
            }

            self.isRunning = false
            if Task.isCancelled {
                self.statusText = "Cancelled."
            } else if self.lastError != nil {
                self.statusText = "Stopped."
            } else {
                self.statusText = "Done — tagged \(Int(done)) wallpaper(s)."
                self.progress = 1
            }
        }
    }

    func cancel() {
        task?.cancel()
    }
}

/// Tiny @AppStorage wrapper for non-View call sites. SwiftUI's @AppStorage
/// only works inside Views, so we route through UserDefaults manually.
@propertyWrapper
struct AppStorageKeyed<Value: Codable> {
    let key: String
    let defaultValue: Value

    init(wrappedValue: Value, _ key: String) {
        self.key = key
        self.defaultValue = wrappedValue
    }

    var wrappedValue: Value {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let value = try? JSONDecoder().decode(Value.self, from: data) else {
                return defaultValue
            }
            return value
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }
}
