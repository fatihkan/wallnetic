import Foundation
import AppKit

/// Owns the AI video generation state and pipeline so `AIGenerateView`
/// stays purely declarative (#166).
///
/// The view keeps its own UI-only state — image picker selection,
/// drag-hover flag, prompt text — but anything that survives a
/// re-render or talks to a service lives here.
@MainActor
final class AIGenerateViewModel: ObservableObject {
    // MARK: - Published state

    @Published var isGenerating = false
    @Published var generationProgress: Double = 0
    @Published var generationStatus: String = ""
    @Published var generatedVideoURL: URL?
    @Published var estimatedTimeRemaining: String = ""
    @Published var errorMessage: String?

    // MARK: - Private state

    private var generationTask: Task<Void, Never>?
    private var generationStartTime: Date?

    // MARK: - Dependencies (injectable for tests)

    private let aiService: AIService
    private let historyManager: GenerationHistoryManager

    init(
        aiService: AIService = .shared,
        historyManager: GenerationHistoryManager = .shared
    ) {
        self.aiService = aiService
        self.historyManager = historyManager
    }

    // MARK: - Generation

    func startGeneration(
        prompt: String,
        model: VideoModel,
        duration: Int,
        aspectRatio: String,
        sourceImage: NSImage?
    ) {
        isGenerating = true
        generationProgress = 0
        generationStatus = "Starting..."
        generationStartTime = Date()
        estimatedTimeRemaining = ""
        errorMessage = nil

        let request = VideoGenerationRequest(
            prompt: prompt,
            model: model,
            duration: duration,
            aspectRatio: aspectRatio,
            sourceImage: sourceImage
        )
        let wasImg2Vid = sourceImage != nil

        generationTask = Task { [weak self] in
            do {
                let result = try await self?.aiService.generateVideo(request: request) { progress, status in
                    Task { @MainActor [weak self] in
                        self?.generationProgress = progress
                        self?.generationStatus = status
                        self?.updateEstimatedTime(progress: progress)
                    }
                }

                if Task.isCancelled { return }

                if let result {
                    self?.historyManager.addGeneration(
                        from: result,
                        wasImg2Vid: wasImg2Vid,
                        aspectRatio: aspectRatio
                    )

                    await MainActor.run { [weak self] in
                        self?.isGenerating = false
                        self?.generationTask = nil
                        self?.generatedVideoURL = result.localURL
                    }
                }
            } catch {
                if Task.isCancelled { return }

                await MainActor.run { [weak self] in
                    self?.isGenerating = false
                    self?.generationTask = nil
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        generationProgress = 0
        generationStatus = ""
        estimatedTimeRemaining = ""
    }

    private func updateEstimatedTime(progress: Double) {
        guard progress > 0.1, let startTime = generationStartTime else {
            estimatedTimeRemaining = ""
            return
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let estimatedTotal = elapsed / progress
        let remaining = estimatedTotal - elapsed

        guard remaining > 0, remaining < 600 else {
            estimatedTimeRemaining = ""
            return
        }

        let seconds = Int(remaining)
        if seconds >= 60 {
            estimatedTimeRemaining = "~\(seconds / 60)m \(seconds % 60)s remaining"
        } else {
            estimatedTimeRemaining = "~\(seconds)s remaining"
        }
    }

    // MARK: - Library import

    /// Copies the generated video into the app's wallpaper library and
    /// asks the manager to refresh. Returns `true` on success, in which
    /// case the caller can clear its prompt / image state.
    @discardableResult
    func addToLibrary(_ videoURL: URL, wallpaperManager: WallpaperManager) -> Bool {
        let libraryURL = applicationSupportURL().appendingPathComponent("Wallnetic/Library")

        do {
            try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)

            let filename = "AI_Video_\(Date().timeIntervalSince1970).mp4"
            let destinationURL = libraryURL.appendingPathComponent(filename)
            try FileManager.default.copyItem(at: videoURL, to: destinationURL)

            wallpaperManager.loadWallpapers()
            generatedVideoURL = nil
            return true
        } catch {
            errorMessage = "Failed to add to library: \(error.localizedDescription)"
            return false
        }
    }

    func clearGeneratedVideo() {
        generatedVideoURL = nil
    }
}
