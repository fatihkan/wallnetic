import Foundation
import AppKit

/// Thread-safe async image loading and caching system
actor AsyncImageCache {
    static let shared = AsyncImageCache()

    private var cache: [String: NSImage] = [:]
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private let maxCacheSize = 100

    /// Loads an image from URL with caching
    func load(from url: URL, size: CGSize? = nil) async -> NSImage? {
        let key = cacheKey(url: url, size: size)

        // Return cached
        if let cached = cache[key] {
            return cached
        }

        // Join in-flight request
        if let existing = inFlight[key] {
            return await existing.value
        }

        // Start new load
        let task = Task<NSImage?, Never> {
            guard let data = try? Data(contentsOf: url) else { return nil }
            guard let image = NSImage(data: data) else { return nil }

            if let size = size {
                let resized = resize(image, to: size)
                return resized
            }
            return image
        }

        inFlight[key] = task
        let result = await task.value
        inFlight.removeValue(forKey: key)

        if let result = result {
            // Evict oldest if over limit
            if cache.count >= maxCacheSize {
                cache.removeValue(forKey: cache.keys.first ?? "")
            }
            cache[key] = result
        }

        return result
    }

    /// Preloads images for a list of URLs
    func preload(urls: [URL], size: CGSize? = nil) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls.prefix(20) {
                group.addTask { _ = await self.load(from: url, size: size) }
            }
        }
    }

    func clearCache() {
        cache.removeAll()
        inFlight.removeAll()
    }

    private func cacheKey(url: URL, size: CGSize?) -> String {
        if let size = size {
            return "\(url.path)_\(Int(size.width))x\(Int(size.height))"
        }
        return url.path
    }

    private func resize(_ image: NSImage, to size: CGSize) -> NSImage {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}
