import Foundation
import AVFoundation

enum WallpaperPackMedia {
    static func validate(_ data: Data, item: WallpaperPackItem) async throws {
        guard data.count == item.bytes, data.count <= WallpaperPackCatalog.maximumMediaBytes,
              WallpaperPackCatalog.digest(data) == item.sha256 else { throw PackError.invalidMedia }
        try validateReferences(data)
        try Task.checkCancellation()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                              attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("verified.mp4")
        try data.write(to: url, options: .withoutOverwriting)
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable), try await !asset.load(.hasProtectedContent),
              try await asset.loadTracks(withMediaType: .audio).isEmpty else { throw PackError.invalidMedia }
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard tracks.count == 1, try await asset.load(.tracks).count == 1 else { throw PackError.invalidMedia }
        let duration = try await asset.load(.duration).seconds
        let size = try await tracks[0].load(.naturalSize)
        let fps = try await tracks[0].load(.nominalFrameRate)
        let descriptions = try await tracks[0].load(.formatDescriptions)
        guard duration.isFinite, abs(duration - item.duration) <= 0.1,
              size.width == CGFloat(item.width), size.height == CGFloat(item.height),
              fps.isFinite, abs(Double(fps) - item.fps) <= 0.1, !descriptions.isEmpty,
              descriptions.allSatisfy({
                  let dimensions = CMVideoFormatDescriptionGetDimensions($0)
                  return CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 &&
                      dimensions.width == item.width && dimensions.height == item.height
              }) else {
            throw PackError.invalidMedia
        }
        try Task.checkCancellation()
    }

    /// Reject reference movies before AVFoundation sees them. This intentionally
    /// accepts a narrow standalone MP4 layout, not arbitrary imported videos.
    static func validateReferences(_ data: Data) throws {
        struct Box { let type: String; let payload: Range<Int> }
        func word(_ offset: Int) -> Int {
            data[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
        }
        func boxes(_ range: Range<Int>) throws -> [Box] {
            var result: [Box] = [], cursor = range.lowerBound
            while cursor < range.upperBound {
                guard range.upperBound - cursor >= 8, result.count < 256 else { throw PackError.invalidMedia }
                var size = word(cursor)
                var header = 8
                if size == 1 {
                    // AVAssetWriter uses a 64-bit mdat size even for small files.
                    // The high word must be zero under our 8 MiB file limit.
                    guard range.upperBound - cursor >= 16, word(cursor + 8) == 0 else { throw PackError.invalidMedia }
                    size = word(cursor + 12)
                    header = 16
                }
                guard size >= header, size <= range.upperBound - cursor,
                      let type = String(data: data[cursor + 4..<cursor + 8], encoding: .ascii) else { throw PackError.invalidMedia }
                result.append(Box(type: type, payload: cursor + header..<cursor + size))
                cursor += size
            }
            return result
        }
        func single(_ type: String, in list: [Box]) throws -> Box {
            let matches = list.filter { $0.type == type }
            guard matches.count == 1 else { throw PackError.invalidMedia }
            return matches[0]
        }
        let top = try boxes(0..<data.count)
        guard top.allSatisfy({ ["ftyp", "free", "mdat", "moov", "wide"].contains($0.type) }) else { throw PackError.invalidMedia }
        _ = try single("ftyp", in: top)
        _ = try single("mdat", in: top)
        let movie = try boxes(single("moov", in: top).payload)
        guard !movie.contains(where: { $0.type == "rmra" }) else { throw PackError.invalidMedia }
        let track = try boxes(single("trak", in: movie).payload)
        let media = try boxes(single("mdia", in: track).payload)
        let info = try boxes(single("minf", in: media).payload)
        let references = try boxes(single("dinf", in: info).payload)
        let reference = try single("dref", in: references).payload
        guard reference.count >= 8, word(reference.lowerBound) == 0,
              word(reference.lowerBound + 4) == 1 else { throw PackError.invalidMedia }
        let entries = try boxes(reference.lowerBound + 8..<reference.upperBound)
        guard entries.count == 1, entries[0].type == "url ", entries[0].payload.count == 4,
              word(entries[0].payload.lowerBound) == 1 else { throw PackError.invalidMedia }
    }
}
