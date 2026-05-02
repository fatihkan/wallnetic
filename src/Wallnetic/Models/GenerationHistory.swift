import Foundation
import AppKit
import AVFoundation

/// Represents a single AI video generation entry in history
struct GenerationHistoryItem: Identifiable, Codable {
    let id: UUID
    let prompt: String
    let model: String
    let modelDisplayName: String
    let videoFilename: String
    let thumbnailFilename: String
    let duration: Int
    let aspectRatio: String
    let wasImg2Vid: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        prompt: String,
        model: VideoModel,
        videoFilename: String,
        thumbnailFilename: String,
        duration: Int,
        aspectRatio: String,
        wasImg2Vid: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.prompt = prompt
        self.model = model.rawValue
        self.modelDisplayName = model.displayName
        self.videoFilename = videoFilename
        self.thumbnailFilename = thumbnailFilename
        self.duration = duration
        self.aspectRatio = aspectRatio
        self.wasImg2Vid = wasImg2Vid
        self.createdAt = createdAt
    }

    /// Full path to the generated video
    var videoURL: URL? {
        GenerationHistoryManager.historyDirectory?.appendingPathComponent(videoFilename)
    }

    /// Full path to the thumbnail
    var thumbnailURL: URL? {
        GenerationHistoryManager.historyDirectory?.appendingPathComponent(thumbnailFilename)
    }

    /// Formatted date string
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    /// Relative time string (e.g., "2 hours ago")
    var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }

    /// Duration formatted as string
    var formattedDuration: String {
        "\(duration)s"
    }

    /// Get VideoModel enum from stored string
    var videoModel: VideoModel? {
        VideoModel(rawValue: model)
    }
}

/// Manager for storing and retrieving video generation history
class GenerationHistoryManager: ObservableObject {
    static let shared = GenerationHistoryManager()

    @Published private(set) var items: [GenerationHistoryItem] = []

    private let historyFilename = "video_generation_history.json"
    private let maxHistoryItems = 50  // Videos are larger, keep fewer

    static var historyDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Wallnetic/History")
    }

    private var historyFileURL: URL? {
        Self.historyDirectory?.appendingPathComponent(historyFilename)
    }

    private init() {
        createHistoryDirectoryIfNeeded()
        loadHistory()
    }

    // MARK: - Directory Management

    private func createHistoryDirectoryIfNeeded() {
        guard let directory = Self.historyDirectory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Load & Save

    private func loadHistory() {
        guard let fileURL = historyFileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            items = []
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            items = try decoder.decode([GenerationHistoryItem].self, from: data)
            // Sort by date, newest first
            items.sort { $0.createdAt > $1.createdAt }
        } catch {
            let errDesc = String(describing: error)
            Log.history.error("Failed to load history: \(errDesc, privacy: .public)")
            items = []
        }
    }

    private func saveHistory() {
        guard let fileURL = historyFileURL else { return }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(items)
            try data.write(to: fileURL)
        } catch {
            let errDesc = String(describing: error)
            Log.history.error("Failed to save history: \(errDesc, privacy: .public)")
        }
    }

    // MARK: - Public Methods

    /// Add a new video generation to history
    func addGeneration(
        videoURL: URL,
        prompt: String,
        model: VideoModel,
        duration: Int,
        aspectRatio: String,
        wasImg2Vid: Bool = false
    ) {
        guard let directory = Self.historyDirectory else { return }

        let id = UUID()
        let timestamp = Date().timeIntervalSince1970
        let videoFilename = "video_\(timestamp)_\(id.uuidString).mp4"
        let thumbnailFilename = "thumb_\(timestamp)_\(id.uuidString).jpg"

        // Copy video to history directory
        let destVideoURL = directory.appendingPathComponent(videoFilename)
        do {
            try FileManager.default.copyItem(at: videoURL, to: destVideoURL)
        } catch {
            let errDesc = String(describing: error)
            Log.history.error("Failed to copy video: \(errDesc, privacy: .public)")
            return
        }

        // Generate thumbnail from video
        let thumbnailURL = directory.appendingPathComponent(thumbnailFilename)
        generateThumbnail(from: destVideoURL, to: thumbnailURL)

        // Create history item
        let item = GenerationHistoryItem(
            id: id,
            prompt: prompt,
            model: model,
            videoFilename: videoFilename,
            thumbnailFilename: thumbnailFilename,
            duration: duration,
            aspectRatio: aspectRatio,
            wasImg2Vid: wasImg2Vid
        )

        // Add to beginning of list
        items.insert(item, at: 0)

        // Trim if over limit
        if items.count > maxHistoryItems {
            let removed = items.removeLast()
            deleteFiles(for: removed)
        }

        saveHistory()
    }

    /// Add from VideoGenerationResult
    func addGeneration(from result: VideoGenerationResult, wasImg2Vid: Bool = false, aspectRatio: String = "16:9") {
        addGeneration(
            videoURL: result.localURL,
            prompt: result.prompt,
            model: result.model,
            duration: result.duration,
            aspectRatio: aspectRatio,
            wasImg2Vid: wasImg2Vid
        )
    }

    /// Delete a specific history item
    func deleteItem(_ item: GenerationHistoryItem) {
        items.removeAll { $0.id == item.id }
        deleteFiles(for: item)
        saveHistory()
    }

    /// Clear all history
    func clearAll() {
        for item in items {
            deleteFiles(for: item)
        }
        items.removeAll()
        saveHistory()
    }

    /// Get thumbnail for a history item
    func getThumbnail(for item: GenerationHistoryItem) -> NSImage? {
        guard let url = item.thumbnailURL else { return nil }
        return NSImage(contentsOf: url)
    }

    // MARK: - Private Helpers

    private func deleteFiles(for item: GenerationHistoryItem) {
        if let videoURL = item.videoURL {
            try? FileManager.default.removeItem(at: videoURL)
        }
        if let thumbnailURL = item.thumbnailURL {
            try? FileManager.default.removeItem(at: thumbnailURL)
        }
    }

    private func generateThumbnail(from videoURL: URL, to thumbnailURL: URL) {
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 320, height: 320)

        do {
            let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

            if let tiffData = nsImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                try jpegData.write(to: thumbnailURL)
            }
        } catch {
            let errDesc = String(describing: error)
            Log.history.error("Failed to generate thumbnail: \(errDesc, privacy: .public)")
        }
    }
}
