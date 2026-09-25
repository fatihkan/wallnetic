import XCTest
import AVFoundation
import AppKit
@testable import Wallnetic

final class HomeGalleryReviewTests: XCTestCase {
    func testFeaturedSelectionSurvivesReordering() {
        let a = Wallpaper(url: URL(fileURLWithPath: "/tmp/a.mp4"))
        let b = Wallpaper(url: URL(fileURLWithPath: "/tmp/b.mp4"))
        XCTAssertEqual(WallpaperBrowsing.selected(in: [a, b], currentID: b.id)?.id, b.id)
        XCTAssertEqual(WallpaperBrowsing.selected(in: [b, a], currentID: b.id)?.id, b.id)
    }

    func testFeaturedSelectionFallsBackImmediatelyAfterRemoval() {
        let a = Wallpaper(url: URL(fileURLWithPath: "/tmp/a.mp4"))
        let removed = Wallpaper(url: URL(fileURLWithPath: "/tmp/removed.mp4"))
        XCTAssertEqual(WallpaperBrowsing.selected(in: [a], currentID: removed.id)?.id, a.id)
        XCTAssertEqual(WallpaperBrowsing.selected(in: [a], currentID: nil)?.id, a.id)
        XCTAssertNil(WallpaperBrowsing.selected(in: [], currentID: removed.id))
    }

    func testFeaturedSelectionUsesUpdatedTitleAndFavorite() {
        var wallpaper = Wallpaper(url: URL(fileURLWithPath: "/tmp/original.mp4"))
        let selection = wallpaper.id
        wallpaper.customTitle = "Renamed wallpaper"
        wallpaper.isFavorite = true
        let displayed = WallpaperBrowsing.selected(in: [wallpaper], currentID: selection)
        XCTAssertEqual(displayed?.displayName, "Renamed wallpaper")
        XCTAssertEqual(displayed?.isFavorite, true)
    }

    func testFeaturedSelectionRecoversWhenItemLeavesFeaturedSubset() {
        let wallpapers = (0..<6).map { Wallpaper(url: URL(fileURLWithPath: "/tmp/\($0).mp4")) }
        let featured = Array(wallpapers.prefix(5))
        let selection = WallpaperBrowsing.selected(in: featured, currentID: wallpapers.last?.id)
        XCTAssertEqual(selection?.id, featured.first?.id)
        XCTAssertEqual(WallpaperBrowsing.adjacent(in: featured, currentID: selection?.id, backwards: true)?.id, featured.last?.id)
    }

    func testPortraitThumbnailPreservesAspectRatio() async throws {
        try await assertThumbnailAspectRatio(width: 64, height: 128)
    }

    func testSquareThumbnailPreservesAspectRatio() async throws {
        try await assertThumbnailAspectRatio(width: 96, height: 96)
    }

    func testLandscapeThumbnailPreservesAspectRatio() async throws {
        try await assertThumbnailAspectRatio(width: 128, height: 64)
    }

    private func assertThumbnailAspectRatio(width: Int, height: Int) async throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("wallnetic-thumbnail-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: source) }
        try await writeVideo(to: source, width: width, height: height)
        let boundingBox = CGSize(width: 320, height: 180)
        let result = await ThumbnailCache.shared.thumbnail(for: source, size: boundingBox)
        let thumbnail = try XCTUnwrap(result)
        XCTAssertEqual(thumbnail.size.width / thumbnail.size.height, CGFloat(width) / CGFloat(height), accuracy: 0.02)
        XCTAssertLessThanOrEqual(thumbnail.size.width, boundingBox.width)
        XCTAssertLessThanOrEqual(thumbnail.size.height, boundingBox.height)
        // Cache hits must retain the same aspect ratio as freshly decoded frames.
        let cachedResult = await ThumbnailCache.shared.thumbnail(for: source, size: boundingBox)
        XCTAssertEqual(cachedResult?.size, thumbnail.size)
        ThumbnailCache.shared.removeThumbnail(for: source)
    }

    private func writeVideo(to url: URL, width: Int, height: Int) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? FixtureError.encodingFailed }
        writer.startSession(atSourceTime: .zero)
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { throw FixtureError.encodingFailed }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, 128, CVPixelBufferGetBytesPerRow(buffer) * height)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        for frame in 0..<2 {
            let deadline = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing, Date() < deadline else {
                    writer.cancelWriting()
                    throw writer.error ?? FixtureError.encodingFailed
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 1)) else {
                writer.cancelWriting()
                throw writer.error ?? FixtureError.encodingFailed
            }
        }
        writer.endSession(atSourceTime: CMTime(value: 2, timescale: 1))
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? FixtureError.encodingFailed }
    }

    private enum FixtureError: Error {
        case encodingFailed
    }
}
