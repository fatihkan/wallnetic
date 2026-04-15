import Foundation
import AVFoundation
import Accelerate
import SwiftUI

/// Captures microphone / audio-input audio, runs FFT, and publishes band
/// magnitudes used by the visualizer overlay.
final class AudioVisualizerManager: ObservableObject {
    static let shared = AudioVisualizerManager()

    static let bandCount: Int = 24

    @AppStorage("audioVisualizer.enabled") var isEnabled: Bool = false
    @AppStorage("audioVisualizer.sensitivity") var sensitivity: Double = 1.0

    @Published var bands: [Float] = Array(repeating: 0, count: bandCount)
    @Published var isRunning: Bool = false
    @Published var permissionDenied: Bool = false

    private let engine = AVAudioEngine()
    private var fftSetup: vDSP_DFT_Setup?
    private let fftSize: Int = 1024
    private var window: [Float] = []
    private var decayBands: [Float] = Array(repeating: 0, count: bandCount)

    private init() {
        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD)
    }

    deinit {
        if let setup = fftSetup { vDSP_DFT_DestroySetup(setup) }
    }

    // MARK: - Control

    func start() {
        guard !isRunning else { return }
        requestPermission { [weak self] granted in
            guard let self else { return }
            if granted {
                self.beginCapture()
            } else {
                self.permissionDenied = true
                self.isEnabled = false
            }
        }
    }

    func stop() {
        isEnabled = false
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        DispatchQueue.main.async {
            self.bands = Array(repeating: 0, count: Self.bandCount)
        }
    }

    func toggle() { isRunning ? stop() : start() }

    // MARK: - Permission

    private func requestPermission(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default: completion(false)
        }
    }

    // MARK: - Capture

    private func beginCapture() {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: format) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }

        do {
            isEnabled = true
            try engine.start()
            isRunning = true
            permissionDenied = false
        } catch {
            NSLog("[AudioVisualizer] engine start failed: %@", error.localizedDescription)
            isRunning = false
        }
    }

    // MARK: - FFT

    private func process(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0],
              let setup = fftSetup else { return }

        let frameCount = min(Int(buffer.frameLength), fftSize)
        var input = [Float](repeating: 0, count: fftSize)
        memcpy(&input, channelData, frameCount * MemoryLayout<Float>.size)
        vDSP_vmul(input, 1, window, 1, &input, 1, vDSP_Length(fftSize))

        let imagIn = [Float](repeating: 0, count: fftSize)
        var realOut = [Float](repeating: 0, count: fftSize)
        var imagOut = [Float](repeating: 0, count: fftSize)
        vDSP_DFT_Execute(setup, input, imagIn, &realOut, &imagOut)

        let bins = fftSize / 2
        var magnitudes = [Float](repeating: 0, count: bins)
        realOut.withUnsafeMutableBufferPointer { rp in
            imagOut.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(bins))
            }
        }

        var scale: Float = 1.0 / Float(fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(bins))

        let newBands = computeBands(from: magnitudes)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for i in 0..<Self.bandCount {
                let target = newBands[i]
                if target > self.decayBands[i] {
                    self.decayBands[i] = target
                } else {
                    self.decayBands[i] = max(0, self.decayBands[i] * 0.82)
                }
            }
            self.bands = self.decayBands
        }
    }

    /// Logarithmic bucketing so low-frequency buckets aren't overwhelmed by bass.
    private func computeBands(from magnitudes: [Float]) -> [Float] {
        let count = Self.bandCount
        let bins = magnitudes.count
        var result = [Float](repeating: 0, count: count)
        let minLog = log10(Float(2))
        let maxLog = log10(Float(bins))
        for i in 0..<count {
            let lo = Int(pow(10, minLog + (maxLog - minLog) * Float(i) / Float(count)))
            let hi = max(lo + 1, Int(pow(10, minLog + (maxLog - minLog) * Float(i + 1) / Float(count))))
            let clampedHi = min(hi, bins)
            guard lo < clampedHi else { continue }
            var sum: Float = 0
            vDSP_meanv(Array(magnitudes[lo..<clampedHi]), 1, &sum, vDSP_Length(clampedHi - lo))
            // Log compress — FFT mags are huge dynamic range
            let scaled = log10(1 + sum * Float(sensitivity) * 2000)
            result[i] = min(1.0, scaled)
        }
        return result
    }
}
