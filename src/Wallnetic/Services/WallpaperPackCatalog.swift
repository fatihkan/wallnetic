import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

enum PackError: LocalizedError {
    case invalidCatalog, invalidMedia, transfer, changedContent, receipts
    var errorDescription: String? {
        switch self {
        case .invalidCatalog: return "This catalog is unsupported or failed validation. The previous catalog is still available."
        case .invalidMedia: return "The wallpaper failed its size, integrity, or video-format check."
        case .transfer: return "The download could not be completed. Check your connection and retry."
        case .changedContent: return "A downloaded file was changed or replaced. It has been kept in your library."
        case .receipts: return "Pack ownership records could not be read or saved. Manage existing files in Library Storage."
        }
    }
}

struct WallpaperPackCatalog: Codable, Equatable, Sendable {
    static let maximumBytes = 512 * 1024
    static let maximumMediaBytes = 8 * 1024 * 1024
    static let updateURL = URL(string: "https://raw.githubusercontent.com/fatihkan/wallnetic/main/catalog/wallpaper-packs-v1.json")!
    let schemaVersion: Int
    let revision: Int
    let packs: [WallpaperPack]

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw PackError.invalidCatalog }
        let catalog: Self
        do { catalog = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw PackError.invalidCatalog }
        guard catalog.schemaVersion == 1, (1...1_000_000).contains(catalog.revision),
              catalog.packs.count <= 20,
              Set(catalog.packs.map(\.id)).count == catalog.packs.count else { throw PackError.invalidCatalog }
        for pack in catalog.packs {
            guard validID(pack.id), validText(pack.name, limit: 80),
                  validText(pack.summary, limit: 240), (1...4).contains(pack.items.count),
                  Set(pack.items.map(\.id)).count == pack.items.count else { throw PackError.invalidCatalog }
            for item in pack.items {
                guard validID(item.id), validText(item.name, limit: 80),
                      validText(item.creator, limit: 100), validText(item.attribution, limit: 200),
                      item.license == "MIT", validMediaURL(item.url),
                      (1...maximumMediaBytes).contains(item.bytes),
                      item.sha256.range(of: "^[a-f0-9]{64}\\z", options: .regularExpression) != nil,
                      (1...3840).contains(item.width), (1...2160).contains(item.height),
                      item.fps.isFinite, item.fps > 0, item.fps <= 30,
                      item.duration.isFinite, item.duration > 0, item.duration <= 30,
                      let preview = Data(base64Encoded: item.previewJPEG), preview.count <= 64 * 1024,
                      let source = CGImageSourceCreateWithData(preview as CFData, nil),
                      CGImageSourceGetType(source) == UTType.jpeg.identifier as CFString,
                      CGImageSourceGetCount(source) == 1,
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight] as? Int,
                      (1...640).contains(width), (1...360).contains(height) else { throw PackError.invalidCatalog }
            }
        }
        return catalog
    }

    static func validID(_ value: String) -> Bool {
        value.range(of: "^[a-z0-9][a-z0-9-]{0,47}\\z", options: .regularExpression) != nil
    }

    private static func validText(_ value: String, limit: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespaces).isEmpty && value.count <= limit &&
            !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) ||
                (0x202A...0x202E).contains($0.value) || (0x2066...0x2069).contains($0.value) }
    }

    static func validMediaURL(_ url: URL) -> Bool {
        // Validate the raw spelling as well as parsed components: no normalization,
        // encoded separators, credentials, alternate hosts, redirects, or branch refs.
        url.absoluteString.range(of: "^https://raw\\.githubusercontent\\.com/fatihkan/wallnetic/[a-f0-9]{40}/catalog/media/[a-z0-9-]{1,48}\\.mp4\\z", options: .regularExpression) != nil
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct WallpaperPack: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let summary: String
    let items: [WallpaperPackItem]
    var bytes: Int { items.reduce(0) { $0 + $1.bytes } }
}

struct WallpaperPackItem: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let creator: String
    let license: String
    let attribution: String
    let url: URL
    let bytes: Int
    let sha256: String
    let width: Int
    let height: Int
    let fps: Double
    let duration: Double
    let previewJPEG: String
}

/// Network requests only occur after an explicit refresh/download action.
/// Each request owns its ephemeral session; cancellation cannot affect another flow.
struct WallpaperPackTransfer {
    var configuration: () -> URLSessionConfiguration = { .ephemeral }

    func fetch(_ url: URL, limit: Int, progress: @escaping @Sendable (Int) async -> Void = { _ in }) async throws -> Data {
        guard url == WallpaperPackCatalog.updateURL || WallpaperPackCatalog.validMediaURL(url),
              limit > 0, limit <= WallpaperPackCatalog.maximumMediaBytes else { throw PackError.transfer }
        let config = configuration()
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 180
        let delegate = NoPackRedirects()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await withTaskCancellationHandler {
            let (bytes, response) = try await session.bytes(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.url == url, response.expectedContentLength <= Int64(limit) else { throw PackError.transfer }
            var data = Data()
            data.reserveCapacity(min(limit, 64 * 1024))
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < limit else { throw PackError.invalidMedia }
                data.append(byte)
                if data.count % (64 * 1024) == 0 { await progress(data.count) }
            }
            try Task.checkCancellation()
            await progress(data.count)
            return data
        } onCancel: { session.invalidateAndCancel() }
    }
}

final class NoPackRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
