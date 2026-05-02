import Foundation
import AVFoundation
import AppKit
import CoreImage
import SwiftUI

/// Represents a wallpaper in the library
struct Wallpaper: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    let url: URL
    let name: String
    var customTitle: String?
    let fileSize: Int64
    var duration: Double?
    var resolution: CGSize?
    let dateAdded: Date
    var isFavorite: Bool
    var dominantColorHex: String?
    var tags: [String]

    /// Display name: customTitle if set, otherwise filename
    var displayName: String {
        customTitle ?? name
    }

    /// Lightweight init — no I/O, no AVFoundation. Safe to call on main thread.
    init(url: URL, isFavorite: Bool = false) {
        self.id = UUID()
        self.url = url
        self.name = url.deletingPathExtension().lastPathComponent
        self.customTitle = nil
        self.tags = []
        self.dateAdded = Date()
        self.isFavorite = isFavorite

        // Only file size — cheap FileManager call
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        self.fileSize = (attributes?[.size] as? Int64) ?? 0

        // Metadata loaded async via loadMetadata()
        self.duration = nil
        self.resolution = nil
    }

    /// Async metadata loading — call after init, off main thread
    mutating func loadMetadata() async {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            self.duration = duration.seconds.isNaN ? nil : duration.seconds

            let tracks = try await asset.loadTracks(withMediaType: .video)
            if let track = tracks.first {
                let naturalSize = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let size = naturalSize.applying(transform)
                self.resolution = CGSize(width: abs(size.width), height: abs(size.height))
            }
        } catch {
            // Metadata unavailable — keep nil defaults. This is the
            // expected path for newly-imported files where AVAsset hasn't
            // loaded the track properties yet, and for files the system
            // can't probe (truncated downloads). Logged at debug level so
            // we can spot if it starts firing for healthy files.
            let pathDescription = url.lastPathComponent
            Log.video.debug("Wallpaper metadata probe skipped for \(pathDescription, privacy: .public): \(String(describing: error), privacy: .public)")
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

    /// Dominant color as NSColor (from hex)
    var dominantColor: NSColor? {
        guard let hex = dominantColorHex else { return nil }
        return NSColor(hex: hex)
    }

    /// Color category for filtering
    var colorCategory: ColorCategory? {
        guard let color = dominantColor else { return nil }
        return ColorCategory.from(color: color)
    }

    // MARK: - Thumbnail Generation

    /// Generates or retrieves cached thumbnail
    func generateThumbnail(size: CGSize = CGSize(width: 320, height: 180)) async -> NSImage? {
        return await ThumbnailCache.shared.thumbnail(for: url, size: size)
    }

    /// Extract dominant color from thumbnail
    func extractDominantColor() async -> String? {
        guard let thumbnail = await generateThumbnail(size: CGSize(width: 64, height: 36)) else { return nil }
        guard let tiffData = thumbnail.tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else { return nil }

        let extent = ciImage.extent
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(cgRect: extent)
        ]), let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())

        return String(format: "#%02X%02X%02X", pixel[0], pixel[1], pixel[2])
    }

    // MARK: - Equatable & Hashable

    static func == (lhs: Wallpaper, rhs: Wallpaper) -> Bool {
        lhs.id == rhs.id && lhs.customTitle == rhs.customTitle && lhs.isFavorite == rhs.isFavorite
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(customTitle)
        hasher.combine(isFavorite)
    }
}

// MARK: - Color Category

enum ColorCategory: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, purple, pink, brown, gray, black, white

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .brown: return .brown
        case .gray: return .gray
        case .black: return Color(white: 0.15)
        case .white: return Color(white: 0.9)
        }
    }

    static func from(color: NSColor) -> ColorCategory {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let r = rgb.redComponent
        let g = rgb.greenComponent
        let b = rgb.blueComponent
        let brightness = (r + g + b) / 3.0
        let saturation = max(r, g, b) - min(r, g, b)

        if brightness < 0.15 { return .black }
        if brightness > 0.85 && saturation < 0.15 { return .white }
        if saturation < 0.12 { return .gray }

        // Determine hue
        var hue: CGFloat = 0
        var sat: CGFloat = 0
        var bri: CGFloat = 0
        rgb.getHue(&hue, saturation: &sat, brightness: &bri, alpha: nil)
        let h = hue * 360

        if h < 15 || h >= 345 { return .red }
        if h < 45 { return .orange }
        if h < 70 { return .yellow }
        if h < 160 { return .green }
        if h < 250 { return .blue }
        if h < 290 { return .purple }
        if h < 345 { return .pink }
        return .red
    }
}

// NSColor.init(hex:) is defined in WallpaperEffectsManager.swift
