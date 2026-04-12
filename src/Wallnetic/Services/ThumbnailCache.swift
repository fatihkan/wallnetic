import AppKit
import AVFoundation

/// Memory-efficient dual-size thumbnail cache with automatic cleanup
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "com.wallnetic.thumbnailcache", qos: .utility)

    private init() {
        // Configure cache limits — dual size means more entries
        cache.countLimit = 120  // ~60 wallpapers × 2 sizes
        cache.totalCostLimit = 80 * 1024 * 1024  // ~80MB max

        // Clear cache on memory pressure
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: NSApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public API

    /// Cache key includes URL + size for dual-size support
    private func cacheKey(for url: URL, size: CGSize) -> NSString {
        "\(url.path)_\(Int(size.width))x\(Int(size.height))" as NSString
    }

    /// Gets a cached thumbnail or generates a new one
    func thumbnail(for url: URL, size: CGSize = CGSize(width: 320, height: 180)) async -> NSImage? {
        let key = cacheKey(for: url, size: size)

        // Check cache first
        if let cached = cache.object(forKey: key) {
            return cached
        }

        // Generate thumbnail
        guard let thumbnail = await generateThumbnail(url: url, size: size) else {
            return nil
        }

        // Cache the result with estimated cost
        let cost = Int(thumbnail.size.width * thumbnail.size.height * 4)  // RGBA
        cache.setObject(thumbnail, forKey: key, cost: cost)

        return thumbnail
    }

    /// Removes all cached thumbnails for a URL (all sizes)
    func removeThumbnail(for url: URL) {
        // Remove common sizes
        for size in [CGSize(width: 320, height: 180), CGSize(width: 160, height: 90),
                     CGSize(width: 64, height: 36), CGSize(width: 44, height: 44),
                     CGSize(width: 48, height: 48), CGSize(width: 112, height: 112),
                     CGSize(width: 128, height: 72), CGSize(width: 200, height: 112)] {
            cache.removeObject(forKey: cacheKey(for: url, size: size))
        }
    }

    /// Clears all cached thumbnails
    func clearCache() {
        cache.removeAllObjects()
    }

    // MARK: - Private

    private func generateThumbnail(url: URL, size: CGSize) async -> NSImage? {
        return await withCheckedContinuation { continuation in
            queue.async {
                let asset = AVURLAsset(url: url)
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true
                imageGenerator.maximumSize = size
                imageGenerator.requestedTimeToleranceBefore = .zero
                imageGenerator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

                do {
                    let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
                    let thumbnail = NSImage(cgImage: cgImage, size: size)
                    continuation.resume(returning: thumbnail)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    @objc private func handleMemoryWarning() {
        // Clear cache on memory pressure
        clearCache()
        print("[ThumbnailCache] Cleared cache due to memory pressure")
    }
}

// MARK: - NSApplication Memory Warning Extension

extension NSApplication {
    static let didReceiveMemoryWarningNotification = Notification.Name("NSApplicationDidReceiveMemoryWarningNotification")
}
