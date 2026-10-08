// Original procedural sample, distributed under the repository's MIT license.
// Run: swift tools/generate-onboarding-sample.swift /path/to/AuroraSample.mp4
import Foundation
import AVFoundation
import CoreImage

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let width = 1280, height = 720, fps: Int32 = 30, frames = 180
let bounds = CGRect(x: 0, y: 0, width: width, height: height)
let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width, AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 900_000,
        AVVideoMaxKeyFrameIntervalKey: 30, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]
])
let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
    sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
writer.add(input)
guard writer.startWriting() else { fatalError("Could not start writer") }
writer.startSession(atSourceTime: .zero)
let context = CIContext(options: [.cacheIntermediates: false])
let background = CIImage(color: CIColor(red: 0.025, green: 0.035, blue: 0.095)).cropped(to: bounds)
for frame in 0..<frames {
    while !input.isReadyForMoreMediaData {
        guard writer.status == .writing else { fatalError("Writer failed") }
        Thread.sleep(forTimeInterval: 0.002)
    }
    autoreleasepool {
        let phase = Double(frame) / Double(frames) * 2 * Double.pi
        var image = background
        for (index, color) in [CIColor(red: 0.15, green: 0.58, blue: 0.85, alpha: 0.9),
                               CIColor(red: 0.53, green: 0.20, blue: 0.76, alpha: 0.75)].enumerated() {
            let offset = Double(index) * Double.pi
            let gradient = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": CIVector(x: 640 + 280 * cos(phase + offset), y: 360 + 150 * sin(phase + offset)),
                "inputRadius0": 15, "inputRadius1": 510,
                "inputColor0": color, "inputColor1": CIColor.clear
            ])!.outputImage!
            image = gradient.composited(over: image).cropped(to: bounds)
        }
        var buffer: CVPixelBuffer?
        guard let pool = adapter.pixelBufferPool,
              CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
              let buffer else { fatalError("Pixel buffer unavailable") }
        context.render(image, to: buffer)
        guard adapter.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: fps)) else {
            fatalError("Frame encoding failed")
        }
    }
}
input.markAsFinished()
let finished = DispatchSemaphore(value: 0)
writer.finishWriting { finished.signal() }
finished.wait()
guard writer.status == .completed else { fatalError("Video encoding failed") }
print(output.path)
