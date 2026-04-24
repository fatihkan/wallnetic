import Foundation
import AVFoundation
import Accelerate
import ScreenCaptureKit
import SwiftUI

/// Captures audio (system output via ScreenCaptureKit, or microphone via
/// AVAudioEngine), runs FFT, and publishes band magnitudes used by the
/// visualizer overlay.
final class AudioVisualizerManager: NSObject, ObservableObject {
    static let shared = AudioVisualizerManager()

    static let bandCount: Int = 64

    enum Source: String, CaseIterable, Identifiable {
        case system, microphone
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: return "System audio"
            case .microphone: return "Microphone"
            }
        }
    }

    @AppStorage("audioVisualizer.enabled") var isEnabled: Bool = false
    @AppStorage("audioVisualizer.sensitivity") var sensitivity: Double = 1.0
    @AppStorage("audioVisualizer.source") private var sourceRaw: String = Source.system.rawValue

    @Published var bands: [Float] = Array(repeating: 0, count: bandCount)
    @Published var peaks: [Float] = Array(repeating: 0, count: bandCount)
    @Published var loudness: Float = 0
    @Published var isRunning: Bool = false
    @Published var permissionDenied: Bool = false
    @Published var lastError: String?

    var source: Source {
        get { Source(rawValue: sourceRaw) ?? .system }
        set {
            sourceRaw = newValue.rawValue
            if isRunning {
                stop()
                start()
            }
        }
    }

    // MARK: - FFT state

    private let fftSize: Int = 1024
    private var fftSetup: vDSP_DFT_Setup?
    private var window: [Float] = []
    private var decayBands: [Float] = Array(repeating: 0, count: bandCount)
    private var peakHold: [Float] = Array(repeating: 0, count: bandCount)
    private var sampleAccumulator: [Float] = []

    // Pre-allocated FFT buffers — reused every cycle to avoid ~280 allocs/sec.
    private var fftWindowed: [Float] = []
    private var fftImagIn: [Float] = []
    private var fftRealOut: [Float] = []
    private var fftImagOut: [Float] = []
    private var fftMagnitudes: [Float] = []
    private var bandResult: [Float] = Array(repeating: 0, count: bandCount)

    // MARK: - Mic capture

    private let engine = AVAudioEngine()

    // MARK: - System capture

    private var scStream: SCStream?
    private let scQueue = DispatchQueue(label: "com.wallnetic.visualizer.sc", qos: .userInitiated)

    // MARK: - Init

    override init() {
        super.init()
        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD)

        // Pre-allocate FFT buffers once.
        fftWindowed = [Float](repeating: 0, count: fftSize)
        fftImagIn = [Float](repeating: 0, count: fftSize)
        fftRealOut = [Float](repeating: 0, count: fftSize)
        fftImagOut = [Float](repeating: 0, count: fftSize)
        fftMagnitudes = [Float](repeating: 0, count: fftSize / 2)
    }

    deinit {
        if let setup = fftSetup { vDSP_DFT_DestroySetup(setup) }
    }

    // MARK: - Control

    func start() {
        guard !isRunning else { return }
        lastError = nil
        switch source {
        case .system:
            startSystemCapture()
        case .microphone:
            requestMicPermission { [weak self] granted in
                guard let self else { return }
                if granted { self.beginMicCapture() }
                else {
                    self.permissionDenied = true
                    self.isEnabled = false
                }
            }
        }
    }

    func stop() {
        isEnabled = false
        stopMicCapture()
        stopSystemCapture()
        DispatchQueue.main.async {
            self.bands = Array(repeating: 0, count: Self.bandCount)
            self.peaks = Array(repeating: 0, count: Self.bandCount)
            self.decayBands = Array(repeating: 0, count: Self.bandCount)
            self.peakHold = Array(repeating: 0, count: Self.bandCount)
            self.loudness = 0
            self.isRunning = false
        }
    }

    func toggle() { isRunning ? stop() : start() }

    // MARK: - Microphone

    private func requestMicPermission(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default: completion(false)
        }
    }

    private func beginMicCapture() {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            lastError = "Input device format is invalid (sampleRate=\(format.sampleRate))"
            isEnabled = false
            return
        }

        input.removeTap(onBus: 0)
        let tapException = WNCatchException { [weak self] in
            input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(self?.fftSize ?? 1024), format: format) { [weak self] buffer, _ in
                self?.ingestMicBuffer(buffer)
            }
        }
        if let ex = tapException {
            lastError = "\(ex.name.rawValue): \(ex.reason ?? "")"
            isEnabled = false
            return
        }

        engine.prepare()
        do {
            try engine.start()
            isEnabled = true
            isRunning = true
        } catch {
            lastError = error.localizedDescription
            input.removeTap(onBus: 0)
        }
    }

    private func stopMicCapture() {
        guard engine.isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func ingestMicBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channel, count: count))
        feed(samples: samples)
    }

    // MARK: - System audio (ScreenCaptureKit)

    private func startSystemCapture() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let display = content.displays.first else {
                    await MainActor.run {
                        self.lastError = "No displays available for capture"
                        self.isEnabled = false
                    }
                    return
                }

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.excludesCurrentProcessAudio = true
                config.sampleRate = 48_000
                config.channelCount = 2
                // SCStream needs a video config even for audio-only; keep it tiny.
                config.width = 2
                config.height = 2
                config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                config.showsCursor = false

                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: self.scQueue)
                // SCStream always produces video frames even when we only want
                // audio — register a no-op screen output so the system doesn't
                // log a -12737 "stream output NOT found" error for every frame.
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.scQueue)
                try await stream.startCapture()

                await MainActor.run {
                    self.scStream = stream
                    self.isEnabled = true
                    self.isRunning = true
                    self.permissionDenied = false
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    // TCC denial usually surfaces here as "The user declined ...".
                    if error.localizedDescription.lowercased().contains("declined") ||
                       error.localizedDescription.lowercased().contains("permission") {
                        self.permissionDenied = true
                    }
                    self.isEnabled = false
                    self.isRunning = false
                }
            }
        }
    }

    private func stopSystemCapture() {
        guard let stream = scStream else { return }
        scStream = nil
        Task { try? await stream.stopCapture() }
    }

    /// Extract a mono Float sample array from an SCStream audio CMSampleBuffer.
    /// ScreenCaptureKit hands us non-interleaved Float32 audio — two buffers
    /// (L/R) when channelCount=2 — so we allocate room for both channels and
    /// average them down to mono.
    private func samples(from sampleBuffer: CMSampleBuffer) -> [Float]? {
        let maxBuffers = 2
        let bufferListPtr = AudioBufferList.allocate(maximumBuffers: maxBuffers)
        defer { free(bufferListPtr.unsafeMutablePointer) }

        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: bufferListPtr.unsafeMutablePointer,
            bufferListSize: AudioBufferList.sizeInBytes(maximumBuffers: maxBuffers),
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        guard let firstData = bufferListPtr[0].mData else { return nil }
        let frameCount = Int(bufferListPtr[0].mDataByteSize) / MemoryLayout<Float>.size
        guard frameCount > 0 else { return nil }

        let left = firstData.assumingMemoryBound(to: Float.self)
        if bufferListPtr.count >= 2, let rightData = bufferListPtr[1].mData {
            let right = rightData.assumingMemoryBound(to: Float.self)
            var mono = [Float](repeating: 0, count: frameCount)
            for i in 0..<frameCount {
                mono[i] = (left[i] + right[i]) * 0.5
            }
            return mono
        } else if bufferListPtr[0].mNumberChannels == 2 {
            // Interleaved stereo in a single buffer.
            let pairCount = frameCount / 2
            var mono = [Float](repeating: 0, count: pairCount)
            for i in 0..<pairCount {
                mono[i] = (left[i * 2] + left[i * 2 + 1]) * 0.5
            }
            return mono
        } else {
            return Array(UnsafeBufferPointer(start: left, count: frameCount))
        }
    }

    // MARK: - FFT pipeline

    /// Accumulate incoming samples up to fftSize, run FFT, emit bands.
    private func feed(samples: [Float]) {
        sampleAccumulator.append(contentsOf: samples)
        while sampleAccumulator.count >= fftSize {
            let chunk = Array(sampleAccumulator.prefix(fftSize))
            sampleAccumulator.removeFirst(fftSize)
            runFFT(on: chunk)
        }
        // Keep accumulator bounded — if we're falling behind, drop oldest data
        if sampleAccumulator.count > fftSize * 4 {
            sampleAccumulator.removeFirst(sampleAccumulator.count - fftSize)
        }
    }

    private func runFFT(on input: [Float]) {
        guard let setup = fftSetup else { return }

        let bins = fftSize / 2

        // Reuse pre-allocated buffers — zero allocs on the hot path.
        vDSP_vmul(input, 1, window, 1, &fftWindowed, 1, vDSP_Length(fftSize))

        // imagIn must be zeroed each cycle (DFT input is real-only).
        vDSP_vclr(&fftImagIn, 1, vDSP_Length(fftSize))
        vDSP_DFT_Execute(setup, fftWindowed, fftImagIn, &fftRealOut, &fftImagOut)

        fftRealOut.withUnsafeMutableBufferPointer { rp in
            fftImagOut.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_zvmags(&split, 1, &fftMagnitudes, 1, vDSP_Length(bins))
            }
        }

        var scale: Float = 1.0 / Float(fftSize)
        vDSP_vsmul(fftMagnitudes, 1, &scale, &fftMagnitudes, 1, vDSP_Length(bins))

        computeBands()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var total: Float = 0
            for i in 0..<Self.bandCount {
                let target = self.bandResult[i]
                // Bar body — fast attack, smooth decay.
                if target > self.decayBands[i] {
                    self.decayBands[i] = self.decayBands[i] + (target - self.decayBands[i]) * 0.55
                } else {
                    self.decayBands[i] = max(0, self.decayBands[i] * 0.85)
                }
                // Peak cap — instant rise, slow linear fall.
                if self.decayBands[i] > self.peakHold[i] {
                    self.peakHold[i] = self.decayBands[i]
                } else {
                    self.peakHold[i] = max(0, self.peakHold[i] - 0.009)
                }
                total += self.decayBands[i]
            }
            self.bands = self.decayBands
            self.peaks = self.peakHold
            self.loudness = min(1, total / Float(Self.bandCount) * 1.4)
        }
    }

    /// Map FFT magnitudes into log-spaced bands. Writes into pre-allocated
    /// `bandResult` and uses pointer arithmetic to avoid per-band slice copies.
    private func computeBands() {
        let count = Self.bandCount
        let bins = fftMagnitudes.count
        let minLog = log10(Float(2))
        let maxLog = log10(Float(bins))
        let sens = Float(sensitivity)

        fftMagnitudes.withUnsafeBufferPointer { magPtr in
            for i in 0..<count {
                let lo = Int(pow(10, minLog + (maxLog - minLog) * Float(i) / Float(count)))
                let hi = max(lo + 1, Int(pow(10, minLog + (maxLog - minLog) * Float(i + 1) / Float(count))))
                let clampedHi = min(hi, bins)
                guard lo < clampedHi else {
                    bandResult[i] = 0
                    continue
                }
                var sum: Float = 0
                vDSP_meanv(magPtr.baseAddress! + lo, 1, &sum, vDSP_Length(clampedHi - lo))
                let scaled = log10(1 + sum * sens * 2000)
                bandResult[i] = min(1.0, scaled)
            }
        }
    }
}

// MARK: - SCStreamOutput / SCStreamDelegate

extension AudioVisualizerManager: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .audio:
            guard let mono = samples(from: sampleBuffer) else {
                NSLog("[AudioVisualizer] failed to extract samples from audio buffer")
                return
            }
            feed(samples: mono)
        default:
            // Screen frames: we only registered to silence the system's
            // "stream output not found" log, so just drop them.
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            self.lastError = error.localizedDescription
            self.isRunning = false
            self.scStream = nil
        }
    }
}
