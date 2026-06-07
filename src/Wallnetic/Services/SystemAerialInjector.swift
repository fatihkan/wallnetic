import AppKit
import AVFoundation
import Foundation
import SwiftUI
import VideoToolbox

/// Plays a real **video** on the macOS lock screen (and Mission Control /
/// Space transitions) by registering the user's wallpaper as a custom
/// *aerial* in macOS's own video-wallpaper system, then pointing the
/// lock-screen ("Idle") slot at it.
///
/// Unlike `SystemWallpaperSync` (a still frame, App-Store-safe), this writes
/// into `~/Library/Application Support/com.apple.wallpaper/` — outside the
/// sandbox container. It therefore works **only in the direct-download
/// (non-sandboxed) build**; `isSupported` is false on the Mac App Store
/// build and the UI hides the feature there.
///
/// Mechanism (validated on macOS 26.4):
///  1. transcode the video to HEVC `.mov` → `aerials/videos/<uuid>.mov`
///  2. append an asset to `aerials/manifest/entries.json`
///  3. patch `Store/Index.plist` so the Idle slots use
///     `com.apple.wallpaper.choice.aerials` + `{assetID: <uuid>}`
///  4. `killall idleassetsd WallpaperAgent` to reload
///
/// Every original file is backed up before the first write; `restore()`
/// puts the user's wallpaper back and removes our injected video.
@MainActor
final class SystemAerialInjector: ObservableObject {
    static let shared = SystemAerialInjector()

    enum InjectorError: LocalizedError {
        case unsupported
        case manifestMissing
        case transcodeFailed(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupported:
                return "Live lock-screen video isn't available in the App Store build."
            case .manifestMissing:
                return "macOS aerial manifest not found. Open System Settings ▸ Wallpaper and pick any aerial once, then try again."
            case .transcodeFailed(let m): return "Couldn't prepare the video: \(m)"
            case .writeFailed(let m): return "Couldn't update the system wallpaper: \(m)"
            }
        }
    }

    /// UUID of the asset we injected (for restore/cleanup), or "".
    @AppStorage("aerial.injectedAssetID") private(set) var injectedAssetID: String = ""
    @Published var isBusy = false

    private let fm = FileManager.default

    private init() {}

    // MARK: - Paths

    /// Real home — in the sandboxed build this resolves to the container
    /// (where the wallpaper store doesn't exist), which is exactly why
    /// `isSupported` returns false there.
    private var wallpaperRoot: URL {
        fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper", isDirectory: true)
    }
    private var entriesURL: URL { wallpaperRoot.appendingPathComponent("aerials/manifest/entries.json") }
    private var indexURL: URL { wallpaperRoot.appendingPathComponent("Store/Index.plist") }
    private var videosDir: URL { wallpaperRoot.appendingPathComponent("aerials/videos", isDirectory: true) }

    private var backupDir: URL {
        applicationSupportURL().appendingPathComponent("Wallnetic/AerialBackup", isDirectory: true)
    }

    // MARK: - Availability

    /// True only on the non-sandboxed build with the macOS aerial system
    /// present and writable.
    var isSupported: Bool {
        if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil { return false }
        return fm.fileExists(atPath: entriesURL.path) && fm.isWritableFile(atPath: videosDir.path)
    }

    var isActive: Bool { !injectedAssetID.isEmpty }

    // MARK: - Public API

    /// Registers `videoURL` as the lock-screen aerial. Long-running
    /// (transcode); call from a Task and surface `isBusy`.
    func setLockScreenVideo(_ videoURL: URL) async throws {
        guard isSupported else { throw InjectorError.unsupported }
        guard fm.fileExists(atPath: entriesURL.path) else { throw InjectorError.manifestMissing }

        isBusy = true
        defer { isBusy = false }

        try backupOriginalsIfNeeded()

        let assetID = UUID().uuidString.uppercased()
        let destVideo = videosDir.appendingPathComponent("\(assetID).mov")

        // 1. Transcode to HEVC .mov (or copy if already HEVC).
        try await Self.prepareHEVC(source: videoURL, destination: destVideo)

        // 2. Best-effort local thumbnail for the picker.
        let thumb = videosDir.appendingPathComponent("\(assetID).jpg")
        let thumbURL = (try? await Self.writeThumbnail(from: videoURL, to: thumb)) ?? nil

        // 3. Append the asset to entries.json.
        do {
            try mergeAsset(id: assetID, label: videoLabel(videoURL), videoURL: destVideo, thumbnailURL: thumbURL)
        } catch {
            try? fm.removeItem(at: destVideo)
            throw InjectorError.writeFailed(error.localizedDescription)
        }

        // 4. Point every Idle (lock screen) slot at our asset.
        do {
            try patchIndexIdle(assetID: assetID)
        } catch {
            throw InjectorError.writeFailed(error.localizedDescription)
        }

        // Clean up a previous injection's leftovers, then record this one.
        cleanupOldVideo(keeping: assetID)
        injectedAssetID = assetID

        reloadDaemons()
        Log.sysWallpaper.info("Lock-screen aerial set: \(assetID, privacy: .public)")
    }

    /// Restores the user's original wallpaper config and removes our video.
    func restore() throws {
        guard isSupported else { throw InjectorError.unsupported }
        let entriesBak = backupDir.appendingPathComponent("entries.json")
        let indexBak = backupDir.appendingPathComponent("Index.plist")

        if fm.fileExists(atPath: entriesBak.path) {
            _ = try? replaceItem(at: entriesURL, with: entriesBak)
        }
        if fm.fileExists(atPath: indexBak.path) {
            _ = try? replaceItem(at: indexURL, with: indexBak)
        }
        cleanupOldVideo(keeping: nil)
        injectedAssetID = ""
        reloadDaemons()
        Log.sysWallpaper.info("Restored original wallpaper, removed injected aerial")
    }

    // MARK: - Backup

    private func backupOriginalsIfNeeded() throws {
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let entriesBak = backupDir.appendingPathComponent("entries.json")
        let indexBak = backupDir.appendingPathComponent("Index.plist")
        // Only snapshot the *pristine* originals — never overwrite a backup
        // with our already-modified files.
        if !fm.fileExists(atPath: entriesBak.path), fm.fileExists(atPath: entriesURL.path) {
            try fm.copyItem(at: entriesURL, to: entriesBak)
        }
        if !fm.fileExists(atPath: indexBak.path), fm.fileExists(atPath: indexURL.path) {
            try fm.copyItem(at: indexURL, to: indexBak)
        }
    }

    // MARK: - entries.json

    private func mergeAsset(id: String, label: String, videoURL: URL, thumbnailURL: URL?) throws {
        let data = try Data(contentsOf: entriesURL)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var assets = root["assets"] as? [[String: Any]] else {
            throw InjectorError.writeFailed("entries.json shape unexpected")
        }
        // Reuse a real category/subcategory so the asset is well-formed.
        let template = assets.first
        let categoryID = (template?["categories"] as? [String])?.first
        let subcategoryID = (template?["subcategories"] as? [String])?.first

        // Drop any previous Wallnetic asset before appending the new one.
        assets.removeAll { ($0["shotID"] as? String)?.hasPrefix("WN_") == true }
        assets.append(Self.makeAssetEntry(
            id: id, label: label, videoURL: videoURL, thumbnailURL: thumbnailURL,
            categoryID: categoryID, subcategoryID: subcategoryID
        ))
        root["assets"] = assets

        let out = try JSONSerialization.data(withJSONObject: root, options: [])
        try out.write(to: entriesURL, options: .atomic)
    }

    // MARK: - Index.plist

    private func patchIndexIdle(assetID: String) throws {
        let data = try Data(contentsOf: indexURL)
        guard let plist = try PropertyListSerialization.propertyList(
            from: data, options: [.mutableContainersAndLeaves], format: nil
        ) as? NSMutableDictionary else {
            throw InjectorError.writeFailed("Index.plist shape unexpected")
        }
        let cfg = try PropertyListSerialization.data(
            fromPropertyList: ["assetID": assetID], format: .binary, options: 0
        )
        let count = Self.applyIdleAerial(to: plist, configuration: cfg, optionValues: Self.aerialOptionValues)
        guard count > 0 else { throw InjectorError.writeFailed("no lock-screen slot found") }

        let out = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try out.write(to: indexURL, options: .atomic)
    }

    // MARK: - Reload

    private func reloadDaemons() {
        for proc in ["idleassetsd", "WallpaperAgent"] {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            task.arguments = [proc]
            task.standardError = FileHandle.nullDevice
            task.standardOutput = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
        }
    }

    // MARK: - Video helpers

    private func cleanupOldVideo(keeping keepID: String?) {
        guard let files = try? fm.contentsOfDirectory(at: videosDir, includingPropertiesForKeys: nil) else { return }
        let prevID = injectedAssetID
        for f in files {
            let base = f.deletingPathExtension().lastPathComponent
            // Only ever delete files we created (the previously-injected id).
            guard base == prevID, base != keepID, !prevID.isEmpty else { continue }
            try? fm.removeItem(at: f)
        }
    }

    private func replaceItem(at dst: URL, with src: URL) throws -> URL? {
        let tmp = dst.appendingPathExtension("wn-tmp")
        try? fm.removeItem(at: tmp)
        try fm.copyItem(at: src, to: tmp)
        _ = try fm.replaceItemAt(dst, withItemAt: tmp)
        return dst
    }

    private func videoLabel(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? "Wallnetic" : name
    }

    // MARK: - Pure helpers (unit-tested)

    /// EncodedOptionValues a real aerial Idle slot carries (decoded bplist:
    /// `{values: {...}}`). Reused verbatim so our slot matches Apple's shape.
    static let aerialOptionValues = Data(base64Encoded:
        "YnBsaXN0MDDRAQJWdmFsdWVz0AgLEgAAAAAAAAEBAAAAAAAAAAMAAAAAAAAAAAAAAAAAAAAT")!

    static let aerialProvider = "com.apple.wallpaper.choice.aerials"

    /// Builds an entries.json asset dict for a local video. `url-4K-SDR-240FPS`
    /// points at the on-disk file via a `file://` URL — the system plays the
    /// pre-placed `videos/<id>.mov` without a network fetch.
    static func makeAssetEntry(
        id: String, label: String, videoURL: URL, thumbnailURL: URL?,
        categoryID: String?, subcategoryID: String?
    ) -> [String: Any] {
        var asset: [String: Any] = [
            "id": id,
            "accessibilityLabel": label,
            "localizedNameKey": "",            // empty → picker falls back to accessibilityLabel
            "shotID": "WN_\(id.prefix(8))",    // WN_ prefix marks it as ours for cleanup
            "preferredOrder": 0,
            "showInTopLevel": true,
            "includeInShuffle": false,         // don't pollute Apple's shuffle pool
            "pointsOfInterest": [:],
            "categories": categoryID.map { [$0] } ?? [],
            "subcategories": subcategoryID.map { [$0] } ?? [],
            "url-4K-SDR-240FPS": videoURL.absoluteString
        ]
        if let thumbnailURL { asset["previewImage"] = thumbnailURL.absoluteString }
        return asset
    }

    /// Recursively rewrites every `Idle.Content` in the wallpaper store to a
    /// single aerial choice for `configuration`. Returns the number patched.
    @discardableResult
    static func applyIdleAerial(to node: Any, configuration: Data, optionValues: Data) -> Int {
        var count = 0
        if let dict = node as? NSMutableDictionary {
            if let idle = dict["Idle"] as? NSMutableDictionary,
               let content = idle["Content"] as? NSMutableDictionary {
                content["Choices"] = [[
                    "Provider": aerialProvider,
                    "Files": [],
                    "Configuration": configuration
                ]]
                content["EncodedOptionValues"] = optionValues
                content["Shuffle"] = "$null"
                count += 1
            }
            for value in dict.allValues {
                count += applyIdleAerial(to: value, configuration: configuration, optionValues: optionValues)
            }
        } else if let array = node as? NSArray {
            for value in array {
                count += applyIdleAerial(to: value, configuration: configuration, optionValues: optionValues)
            }
        }
        return count
    }

    // MARK: - Transcode

    /// Writes a destination `.mov` that matches macOS aerial assets closely
    /// enough to actually *play* (not just show a poster frame): HEVC `hvc1`,
    /// 10-bit Main10, Rec.709 SDR, and crucially **no audio track**.
    ///
    /// `AVAssetExportSession`'s HEVC preset produces an 8-bit stream that
    /// carries the source audio; the aerial player renders those as a single
    /// static frame. Driving an `AVAssetReader`→`AVAssetWriter` pipeline lets
    /// us drop audio and force the 10-bit profile Apple's own aerials use.
    nonisolated static func prepareHEVC(source: URL, destination: URL) async throws {
        try? FileManager.default.removeItem(at: destination)

        let asset = AVURLAsset(url: source)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw InjectorError.transcodeFailed("source has no video track")
        }
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        // HEVC needs even dimensions.
        let width = Int(abs(naturalSize.width).rounded(.down)) & ~1
        let height = Int(abs(naturalSize.height).rounded(.down)) & ~1
        guard width > 0, height > 0 else { throw InjectorError.transcodeFailed("bad video size") }

        let reader = try AVAssetReader(asset: asset)
        // Decode to 10-bit so the encoder can emit Main10 even from 8-bit input.
        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        ])
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else { throw InjectorError.transcodeFailed("cannot read video") }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String,
                AVVideoAverageBitRateKey: 12_000_000
            ]
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        writerInput.expectsMediaDataInRealTime = false
        writerInput.transform = transform   // keep orientation; no audio input → no audio track
        guard writer.canAdd(writerInput) else { throw InjectorError.transcodeFailed("cannot configure HEVC writer") }
        writer.add(writerInput)

        guard reader.startReading() else {
            throw InjectorError.transcodeFailed(reader.error?.localizedDescription ?? "reader start failed")
        }
        guard writer.startWriting() else {
            throw InjectorError.transcodeFailed(writer.error?.localizedDescription ?? "writer start failed")
        }
        writer.startSession(atSourceTime: .zero)

        // Pump samples in a plain async loop — avoids requestMediaDataWhenReady's
        // @Sendable closure capturing the non-Sendable reader/writer (which the
        // Xcode 15.2 CI rejects). copyNextSampleBuffer blocks per frame; we yield
        // while the encoder drains.
        while reader.status == .reading {
            guard let sample = readerOutput.copyNextSampleBuffer() else { break }
            while !writerInput.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            writerInput.append(sample)
        }
        writerInput.markAsFinished()

        await writer.finishWriting()
        guard writer.status == .completed else {
            throw InjectorError.transcodeFailed(writer.error?.localizedDescription ?? "writer status \(writer.status.rawValue)")
        }
        if reader.status == .failed {
            throw InjectorError.transcodeFailed(reader.error?.localizedDescription ?? "reader failed")
        }
    }

    nonisolated static func writeThumbnail(from videoURL: URL, to dest: URL) async throws -> URL? {
        let asset = AVURLAsset(url: videoURL)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1280, height: 800)
        guard let (cg, _) = try? await gen.image(at: CMTime(seconds: 1, preferredTimescale: 600)) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return nil }
        try data.write(to: dest, options: .atomic)
        return dest
    }
}
