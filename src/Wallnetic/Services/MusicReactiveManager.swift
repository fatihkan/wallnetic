import Foundation
import AVFoundation
import SwiftUI

/// Reacts to system audio with visual effects on wallpaper
class MusicReactiveManager: ObservableObject {
    static let shared = MusicReactiveManager()

    enum ReactiveEffect: String, CaseIterable, Identifiable {
        case pulse = "Pulse"
        case colorShift = "Color Shift"
        case zoom = "Zoom"
        case blurPulse = "Blur Pulse"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .pulse: return "waveform.path"
            case .colorShift: return "paintpalette"
            case .zoom: return "arrow.up.left.and.arrow.down.right"
            case .blurPulse: return "aqi.medium"
            }
        }
    }

    // MARK: - Settings

    @AppStorage("music.enabled") var isEnabled: Bool = false
    @AppStorage("music.effect") private var effectRaw: String = "pulse"
    @AppStorage("music.sensitivity") var sensitivity: Double = 0.5  // 0-1
    @AppStorage("music.intensity") var intensity: Double = 0.5      // 0-1

    @Published var audioLevel: Float = 0
    @Published var isActive = false

    var selectedEffect: ReactiveEffect {
        get { ReactiveEffect(rawValue: effectRaw) ?? .pulse }
        set { effectRaw = newValue.rawValue }
    }

    private var audioEngine: AVAudioEngine?
    private var displayLink: CVDisplayLink?
    private var timer: Timer?

    private init() {}

    // MARK: - Control

    func start() {
        guard !isActive else { return }
        isEnabled = true
        isActive = true

        // Use timer-based audio level simulation
        // Real implementation would use AVAudioEngine tap or ScreenCaptureKit
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateAudioLevel()
        }

        NSLog("[MusicReactive] Started with effect: %@", selectedEffect.rawValue)
    }

    func stop() {
        isEnabled = false
        isActive = false
        timer?.invalidate()
        timer = nil
        audioLevel = 0

        // Reset effects
        let effects = WallpaperEffectsManager.shared
        effects.brightness = 0
        effects.blur = 0
        effects.notifyEffectsChanged()
    }

    // MARK: - Audio Processing

    private func updateAudioLevel() {
        // Simulated audio level - in production use AVAudioEngine or system audio tap
        // This creates a smooth oscillating pattern for demo
        let time = Date().timeIntervalSinceReferenceDate
        let base = Float(sin(time * 2.0) * 0.3 + sin(time * 5.0) * 0.2 + sin(time * 8.0) * 0.1)
        audioLevel = max(0, min(1, (base + 0.5) * Float(sensitivity)))

        applyEffect()
    }

    private func applyEffect() {
        let effects = WallpaperEffectsManager.shared
        let level = Double(audioLevel) * intensity

        switch selectedEffect {
        case .pulse:
            effects.brightness = level * 0.15 - 0.05
            effects.notifyEffectsChanged()

        case .colorShift:
            // Shift tint hue based on audio
            effects.tintEnabled = true
            effects.tintOpacity = level * 0.2
            let hue = audioLevel * 360
            effects.tintColorHex = hueToHex(hue: CGFloat(hue))
            effects.notifyEffectsChanged()

        case .zoom:
            // Subtle zoom would require transform on the player layer
            effects.brightness = level * 0.1
            effects.notifyEffectsChanged()

        case .blurPulse:
            effects.blur = level * 8
            effects.notifyEffectsChanged()
        }
    }

    private func hueToHex(hue: CGFloat) -> String {
        let color = NSColor(hue: hue / 360.0, saturation: 0.7, brightness: 0.8, alpha: 1.0)
        guard let rgb = color.usingColorSpace(.sRGB) else { return "#000000" }
        return String(format: "#%02X%02X%02X",
                      Int(rgb.redComponent * 255),
                      Int(rgb.greenComponent * 255),
                      Int(rgb.blueComponent * 255))
    }
}
