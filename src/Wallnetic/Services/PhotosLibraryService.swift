import Foundation
import Photos
import AppKit

/// Wraps Apple Photos framework access for the Memories integration (#137).
/// Handles authorization, lazy album/asset fetching, and thumbnail loading.
///
/// Authorization is requested once via `requestAuthorization`; callers should
/// branch on the returned status and present a Settings deep-link if denied.
@MainActor
final class PhotosLibraryService: ObservableObject {
    static let shared = PhotosLibraryService()

    @Published private(set) var authStatus: PHAuthorizationStatus = .notDetermined

    private let imageManager = PHCachingImageManager()

    private init() {
        authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    // MARK: - Authorization

    func requestAuthorization() async -> PHAuthorizationStatus {
        let status = await withCheckedContinuation { (cont: CheckedContinuation<PHAuthorizationStatus, Never>) in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                cont.resume(returning: status)
            }
        }
        await MainActor.run { self.authStatus = status }
        return status
    }

    var isAuthorized: Bool {
        authStatus == .authorized || authStatus == .limited
    }

    // MARK: - Albums

    /// Returns user-created albums plus the synthetic "Recents" smart album.
    func fetchAlbums() -> [AlbumDescriptor] {
        var result: [AlbumDescriptor] = []

        // Recents smart album (most recent media)
        let recents = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumUserLibrary,
            options: nil
        )
        if let collection = recents.firstObject {
            result.append(AlbumDescriptor(collection: collection, displayName: "Recents"))
        }

        // Favorites smart album
        let favorites = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumFavorites,
            options: nil
        )
        if let collection = favorites.firstObject {
            result.append(AlbumDescriptor(collection: collection, displayName: "Favorites"))
        }

        // User-created albums
        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: nil
        )
        userAlbums.enumerateObjects { collection, _, _ in
            let name = collection.localizedTitle ?? "Album"
            result.append(AlbumDescriptor(collection: collection, displayName: name))
        }

        return result
    }

    /// Fetches image-only assets in the given album, newest first.
    /// Limited to `limit` results to keep grid render fast — the user can
    /// search/filter inside their library if they need older items.
    func fetchAssets(in album: AlbumDescriptor, limit: Int = 300) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.fetchLimit = limit

        let result = PHAsset.fetchAssets(in: album.collection, options: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    // MARK: - Thumbnails

    /// Loads a square thumbnail for the asset at the requested point size
    /// (the manager scales by display scale internally). The completion is
    /// always invoked on the main queue exactly once with the final
    /// (non-degraded) image — the opportunistic low-res placeholder is
    /// skipped to avoid grid flicker.
    func requestThumbnail(for asset: PHAsset, targetSize: CGSize, completion: @escaping (NSImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            // Skip the low-res preview pass; only deliver the final image.
            if let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool, isDegraded {
                return
            }
            DispatchQueue.main.async { completion(image) }
        }
    }

    /// Drops every cached thumbnail. Call when the photo grid disappears.
    func flushThumbnailCache() {
        imageManager.stopCachingImagesForAllAssets()
    }

    /// Loads a full-size image for slideshow rendering.
    func requestFullImage(for asset: PHAsset) async -> NSImage? {
        await withCheckedContinuation { (cont: CheckedContinuation<NSImage?, Never>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            imageManager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                // Skip the low-res "opportunistic" preview if a degraded flag is set.
                if let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool, isDegraded {
                    return
                }
                cont.resume(returning: image)
            }
        }
    }
}

// MARK: - Models

struct AlbumDescriptor: Identifiable, Hashable {
    let collection: PHAssetCollection
    let displayName: String

    var id: String { collection.localIdentifier }

    static func == (lhs: AlbumDescriptor, rhs: AlbumDescriptor) -> Bool {
        lhs.collection.localIdentifier == rhs.collection.localIdentifier
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(collection.localIdentifier)
    }
}
