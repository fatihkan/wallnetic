import Foundation
import AppKit

/// Represents a single AI generation entry in history
struct GenerationHistoryItem: Identifiable, Codable {
    let id: UUID
    let prompt: String
    let styleId: String
    let styleName: String
    let provider: String
    let imageFilename: String
    let thumbnailFilename: String
    let width: Int
    let height: Int
    let strength: Double?
    let wasImg2Img: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        prompt: String,
        styleId: String,
        styleName: String,
        provider: String,
        imageFilename: String,
        thumbnailFilename: String,
        width: Int,
        height: Int,
        strength: Double? = nil,
        wasImg2Img: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.prompt = prompt
        self.styleId = styleId
        self.styleName = styleName
        self.provider = provider
        self.imageFilename = imageFilename
        self.thumbnailFilename = thumbnailFilename
        self.width = width
        self.height = height
        self.strength = strength
        self.wasImg2Img = wasImg2Img
        self.createdAt = createdAt
    }

    /// Full path to the generated image
    var imageURL: URL? {
        GenerationHistoryManager.historyDirectory?.appendingPathComponent(imageFilename)
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
}

/// Manager for storing and retrieving generation history
class GenerationHistoryManager: ObservableObject {
    static let shared = GenerationHistoryManager()

    @Published private(set) var items: [GenerationHistoryItem] = []

    private let historyFilename = "generation_history.json"
    private let maxHistoryItems = 100

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
            print("Failed to load history: \(error)")
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
            print("Failed to save history: \(error)")
        }
    }

    // MARK: - Public Methods

    /// Add a new generation to history
    func addGeneration(
        image: NSImage,
        prompt: String,
        style: AIStyle,
        provider: AIProvider,
        width: Int,
        height: Int,
        strength: Double? = nil,
        wasImg2Img: Bool = false
    ) {
        guard let directory = Self.historyDirectory else { return }

        let id = UUID()
        let timestamp = Date().timeIntervalSince1970
        let imageFilename = "gen_\(timestamp)_\(id.uuidString).png"
        let thumbnailFilename = "thumb_\(timestamp)_\(id.uuidString).png"

        // Save full image
        let imageURL = directory.appendingPathComponent(imageFilename)
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            try? pngData.write(to: imageURL)
        }

        // Create and save thumbnail
        let thumbnail = createThumbnail(from: image, maxSize: 200)
        let thumbnailURL = directory.appendingPathComponent(thumbnailFilename)
        if let tiffData = thumbnail.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
            try? jpegData.write(to: thumbnailURL)
        }

        // Create history item
        let item = GenerationHistoryItem(
            id: id,
            prompt: prompt,
            styleId: style.id,
            styleName: style.name,
            provider: provider.rawValue,
            imageFilename: imageFilename,
            thumbnailFilename: thumbnailFilename,
            width: width,
            height: height,
            strength: strength,
            wasImg2Img: wasImg2Img
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

    /// Get image for a history item
    func getImage(for item: GenerationHistoryItem) -> NSImage? {
        guard let url = item.imageURL else { return nil }
        return NSImage(contentsOf: url)
    }

    /// Get thumbnail for a history item
    func getThumbnail(for item: GenerationHistoryItem) -> NSImage? {
        guard let url = item.thumbnailURL else { return nil }
        return NSImage(contentsOf: url)
    }

    // MARK: - Private Helpers

    private func deleteFiles(for item: GenerationHistoryItem) {
        if let imageURL = item.imageURL {
            try? FileManager.default.removeItem(at: imageURL)
        }
        if let thumbnailURL = item.thumbnailURL {
            try? FileManager.default.removeItem(at: thumbnailURL)
        }
    }

    private func createThumbnail(from image: NSImage, maxSize: CGFloat) -> NSImage {
        let width = image.size.width
        let height = image.size.height

        let ratio = min(maxSize / width, maxSize / height)
        let newSize = NSSize(width: width * ratio, height: height * ratio)

        let thumbnail = NSImage(size: newSize)
        thumbnail.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        thumbnail.unlockFocus()

        return thumbnail
    }
}
