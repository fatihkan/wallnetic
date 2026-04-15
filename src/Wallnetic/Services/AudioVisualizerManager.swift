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

    static let bandCount: Int = 24

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
    private var sampleAccumulator: [Float] = []

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
            self.decayBands = Array(repeating: 0, count: Self.bandCount)
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
    /// (L/R) when channelCount=2 — so we average the channels down to mono.
    private func samples(from sampleBuffer: CMSampleBuffer) -> [Float]? {
        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let abl = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        guard let firstPtr = abl.first?.mData else { return nil }
        let frameCount = Int(abl[0].mDataByteSize) / MemoryLayout<Float>.size
        guard frameCount > 0 else { return nil }

        let left = firstPtr.assumingMemoryBound(to: Float.self)
        if abl.count >= 2, let rightPtr = abl[1].mData {
            let right = rightPtr.assumingMemoryBound(to: Float.self)
            var mono = [Float](repeating: 0, count: frameCount)
            for i in 0..<frameCount {
                mono[i] = (left[i] + right[i]) * 0.5
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

        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(input, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        let imagIn = [Float](repeating: 0, count: fftSize)
        var realOut = [Float](repeating: 0, count: fftSize)
        var imagOut = [Float](repeating: 0, count: fftSize)
        vDSP_DFT_Execute(setup, windowed, imagIn, &realOut, &imagOut)

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
            let scaled = log10(1 + sum * Float(sensitivity) * 2000)
            result[i] = min(1.0, scaled)
        }
        return result
    }
}

// MARK: - SCStreamOutput / SCStreamDelegate

extension AudioVisualizerManager: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let mono = samples(from: sampleBuffer) else { return }
        feed(samples: mono)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            self.lastError = error.localizedDescription
            self.isRunning = false
            self.scStream = nil
        }
    }
}
