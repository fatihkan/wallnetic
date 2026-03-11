import AppKit
import AVFoundation

/// Memory-efficient thumbnail cache with automatic cleanup
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSURL, NSImage>()
    private let queue = DispatchQueue(label: "com.wallnetic.thumbnailcache", qos: .utility)

    private init() {
        // Configure cache limits
        cache.countLimit = 50  // Max 50 thumbnails
        cache.totalCostLimit = 50 * 1024 * 1024  // ~50MB max

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

    /// Gets a cached thumbnail or generates a new one
    func thumbnail(for url: URL, size: CGSize = CGSize(width: 320, height: 180)) async -> NSImage? {
        let cacheKey = url as NSURL

        // Check cache first
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        // Generate thumbnail
        guard let thumbnail = await generateThumbnail(url: url, size: size) else {
            return nil
        }

        // Cache the result with estimated cost
        let cost = Int(thumbnail.size.width * thumbnail.size.height * 4)  // RGBA
        cache.setObject(thumbnail, forKey: cacheKey, cost: cost)

        return thumbnail
    }

    /// Removes a specific thumbnail from cache
    func removeThumbnail(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
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
