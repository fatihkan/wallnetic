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
        setupMemoryPressureMonitor()
    }

    private var memoryPressureSource: DispatchSourceMemoryPressure?

    private func setupMemoryPressureMonitor() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            self?.clearCache()
            print("[ThumbnailCache] Cleared cache due to memory pressure")
        }
        source.resume()
        memoryPressureSource = source
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
        let asset = AVURLAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = size
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        do {
            let (cgImage, _) = try await imageGenerator.image(at: .zero)
            return NSImage(cgImage: cgImage, size: size)
        } catch {
            return nil
        }
    }

}
