import Foundation
import AVFoundation
import AppKit

/// Represents a wallpaper in the library
struct Wallpaper: Identifiable, Equatable, Hashable {
    let id: UUID
    let url: URL
    let name: String
    let fileSize: Int64
    let duration: Double?
    let resolution: CGSize?
    let dateAdded: Date

    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.name = url.deletingPathExtension().lastPathComponent
        self.dateAdded = Date()

        // Get file size
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        self.fileSize = (attributes?[.size] as? Int64) ?? 0

        // Get video metadata
        let asset = AVAsset(url: url)
        self.duration = asset.duration.seconds.isNaN ? nil : asset.duration.seconds

        // Get resolution from first video track
        if let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            self.resolution = CGSize(width: abs(size.width), height: abs(size.height))
        } else {
            self.resolution = nil
        }
    }

    // MARK: - Computed Properties

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var formattedDuration: String {
        guard let duration = duration else { return "--:--" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedResolution: String {
        guard let resolution = resolution else { return "Unknown" }
        return "\(Int(resolution.width))×\(Int(resolution.height))"
    }

    // MARK: - Thumbnail Generation

    func generateThumbnail(size: CGSize = CGSize(width: 320, height: 180)) async -> NSImage? {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = size

        do {
            let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
            return NSImage(cgImage: cgImage, size: size)
        } catch {
            print("Failed to generate thumbnail: \(error)")
            return nil
        }
    }

    // MARK: - Equatable & Hashable

    static func == (lhs: Wallpaper, rhs: Wallpaper) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
