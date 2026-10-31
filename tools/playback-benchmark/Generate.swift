// Original procedural media, MIT licensed under the repository LICENSE.
// Fixed geometry and motion; encoded bytes depend on the OS/encoder.
import AVFoundation
import CoreImage
import Foundation

enum FixtureError: Error { case invalidArguments, encoding(String) }

@main struct Generate {
    static func main() {
        do { try generate() }
        catch {
            FileHandle.standardError.write(Data("Fixture error: \(error)\n".utf8))
            exit(1)
        }
    }

    static func generate() throws {
        let args = CommandLine.arguments
        guard args.count == 3, ["h264", "hevc"].contains(args[1]),
              !FileManager.default.fileExists(atPath: args[2]) else {
            throw FixtureError.invalidArguments
        }
        let hevc = args[1] == "hevc"
        let width = hevc ? 3840 : 1920, height = hevc ? 2160 : 1080
        let fps: Int32 = hevc ? 60 : 30
        let frames = Int(fps) * 10
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let output = URL(fileURLWithPath: args[2])
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        var finished = false
        defer { if !finished { writer.cancelWriting() } }
        let settings: [String: Any] = [
            AVVideoCodecKey: hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: hevc ? 16_000_000 : 6_000_000,
                AVVideoMaxKeyFrameIntervalKey: Int(fps), AVVideoExpectedSourceFrameRateKey: Int(fps)]
        ]
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
            throw FixtureError.encoding("Requested encoder unavailable; no codec or resolution fallback")
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
        guard writer.canAdd(input) else { throw FixtureError.encoding("Cannot add video input") }
        writer.add(input)
        guard writer.startWriting() else { throw FixtureError.encoding("Cannot start writer") }
        writer.startSession(atSourceTime: .zero)
        let context = CIContext(options: [.cacheIntermediates: false])
        let background = CIImage(color: CIColor(red: 0.05, green: 0.10, blue: 0.20)).cropped(to: bounds)
        let deadline = ProcessInfo.processInfo.systemUptime + 300
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing, ProcessInfo.processInfo.systemUptime < deadline else {
                    throw FixtureError.encoding(writer.error?.localizedDescription ?? "Encoder timed out")
                }
                Thread.sleep(forTimeInterval: 0.002)
            }
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw FixtureError.encoding("Encoder timed out") }
            try autoreleasepool {
                let phase = Double(frame) / Double(frames) * 2 * Double.pi
                var image = background
                for index in 0..<2 {
                    let offset = Double(index) * Double.pi
                    guard let gradient = CIFilter(name: "CIRadialGradient", parameters: [
                        "inputCenter": CIVector(x: Double(width) * (0.5 + 0.25 * cos(phase + offset)),
                            y: Double(height) * (0.5 + 0.25 * sin(phase + offset))),
                        "inputRadius0": Double(width) * 0.01, "inputRadius1": Double(width) * 0.4,
                        "inputColor0": CIColor(red: 0.1, green: index == 0 ? 0.8 : 0.3, blue: 0.7, alpha: 0.85),
                        "inputColor1": CIColor.clear
                    ])?.outputImage else { throw FixtureError.encoding("Gradient unavailable") }
                    image = gradient.composited(over: image).cropped(to: bounds)
                }
                var buffer: CVPixelBuffer?
                guard let pool = adapter.pixelBufferPool,
                      CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                      let buffer else { throw FixtureError.encoding("Pixel buffer unavailable") }
                context.render(image, to: buffer, bounds: bounds, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
                guard adapter.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: fps)) else {
                    throw FixtureError.encoding(writer.error?.localizedDescription ?? "Append failed")
                }
            }
        }
        writer.endSession(atSourceTime: CMTime(value: 10, timescale: 1))
        input.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        guard semaphore.wait(timeout: .now() + 60) == .success, writer.status == .completed else {
            throw FixtureError.encoding(writer.error?.localizedDescription ?? "Finish timed out")
        }
        finished = true
    }
}
