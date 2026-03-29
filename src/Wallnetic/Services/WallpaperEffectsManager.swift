import Foundation
import SwiftUI
import CoreImage

/// Manages visual effects applied to wallpaper videos
class WallpaperEffectsManager: ObservableObject {
    static let shared = WallpaperEffectsManager()

    // MARK: - Effect Properties

    @AppStorage("effect.brightness") var brightness: Double = 0       // -0.5 to 0.5
    @AppStorage("effect.contrast") var contrast: Double = 1.0         // 0.5 to 2.0
    @AppStorage("effect.saturation") var saturation: Double = 1.0     // 0.0 to 2.0
    @AppStorage("effect.blur") var blur: Double = 0                   // 0 to 20
    @AppStorage("effect.tintEnabled") var tintEnabled: Bool = false
    @AppStorage("effect.tintColorHex") var tintColorHex: String = "#000000"
    @AppStorage("effect.tintOpacity") var tintOpacity: Double = 0.3   // 0 to 0.8
    @AppStorage("effect.vignetteEnabled") var vignetteEnabled: Bool = false
    @AppStorage("effect.vignetteIntensity") var vignetteIntensity: Double = 0.5  // 0 to 2
    @AppStorage("effect.activePreset") var activePreset: String = "none"

    var hasActiveEffects: Bool {
        brightness != 0 || contrast != 1.0 || saturation != 1.0 ||
        blur > 0 || tintEnabled || vignetteEnabled
    }

    // MARK: - Presets

    struct EffectPreset: Identifiable {
        let id: String
        let name: String
        let icon: String
        let brightness: Double
        let contrast: Double
        let saturation: Double
        let blur: Double
        let tintEnabled: Bool
        let tintColorHex: String
        let tintOpacity: Double
        let vignetteEnabled: Bool
        let vignetteIntensity: Double
    }

    static let presets: [EffectPreset] = [
        EffectPreset(id: "none", name: "None", icon: "circle.slash",
                     brightness: 0, contrast: 1.0, saturation: 1.0,
                     blur: 0, tintEnabled: false, tintColorHex: "#000000",
                     tintOpacity: 0, vignetteEnabled: false, vignetteIntensity: 0),
        EffectPreset(id: "dim", name: "Dim", icon: "moon",
                     brightness: -0.2, contrast: 0.95, saturation: 0.9,
                     blur: 0, tintEnabled: false, tintColorHex: "#000000",
                     tintOpacity: 0, vignetteEnabled: true, vignetteIntensity: 0.5),
        EffectPreset(id: "vivid", name: "Vivid", icon: "paintpalette",
                     brightness: 0.05, contrast: 1.2, saturation: 1.5,
                     blur: 0, tintEnabled: false, tintColorHex: "#000000",
                     tintOpacity: 0, vignetteEnabled: false, vignetteIntensity: 0),
        EffectPreset(id: "moody", name: "Moody", icon: "cloud.moon",
                     brightness: -0.15, contrast: 1.1, saturation: 0.7,
                     blur: 0, tintEnabled: true, tintColorHex: "#1a0a2e",
                     tintOpacity: 0.2, vignetteEnabled: true, vignetteIntensity: 1.0),
        EffectPreset(id: "film", name: "Film", icon: "film",
                     brightness: -0.05, contrast: 1.15, saturation: 0.85,
                     blur: 0, tintEnabled: true, tintColorHex: "#2d1f0e",
                     tintOpacity: 0.15, vignetteEnabled: true, vignetteIntensity: 0.8),
        EffectPreset(id: "bw", name: "B&W", icon: "circle.lefthalf.filled",
                     brightness: 0.05, contrast: 1.2, saturation: 0,
                     blur: 0, tintEnabled: false, tintColorHex: "#000000",
                     tintOpacity: 0, vignetteEnabled: false, vignetteIntensity: 0),
        EffectPreset(id: "dreamy", name: "Dreamy", icon: "sparkles",
                     brightness: 0.1, contrast: 0.9, saturation: 1.2,
                     blur: 3, tintEnabled: true, tintColorHex: "#1e0533",
                     tintOpacity: 0.1, vignetteEnabled: true, vignetteIntensity: 0.6),
        EffectPreset(id: "focus", name: "Focus", icon: "eye",
                     brightness: -0.1, contrast: 1.0, saturation: 1.0,
                     blur: 8, tintEnabled: false, tintColorHex: "#000000",
                     tintOpacity: 0, vignetteEnabled: false, vignetteIntensity: 0),
    ]

    // MARK: - Apply Preset

    func applyPreset(_ preset: EffectPreset) {
        withAnimation(.easeInOut(duration: 0.3)) {
            brightness = preset.brightness
            contrast = preset.contrast
            saturation = preset.saturation
            blur = preset.blur
            tintEnabled = preset.tintEnabled
            tintColorHex = preset.tintColorHex
            tintOpacity = preset.tintOpacity
            vignetteEnabled = preset.vignetteEnabled
            vignetteIntensity = preset.vignetteIntensity
            activePreset = preset.id
        }
        objectWillChange.send()
        notifyEffectsChanged()
    }

    func resetEffects() {
        applyPreset(Self.presets[0])
    }

    // MARK: - Notification

    func notifyEffectsChanged() {
        NotificationCenter.default.post(name: .wallpaperEffectsDidChange, object: nil)
    }

    // MARK: - Tint Color Helper

    var tintColor: NSColor {
        NSColor(hex: tintColorHex) ?? .black
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let wallpaperEffectsDidChange = Notification.Name("wallpaperEffectsDidChange")
}

// MARK: - NSColor Hex Extension

extension NSColor {
    convenience init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexString = hexString.replacingOccurrences(of: "#", with: "")

        guard hexString.count == 6,
              let hexInt = UInt64(hexString, radix: 16) else { return nil }

        let r = CGFloat((hexInt >> 16) & 0xFF) / 255.0
        let g = CGFloat((hexInt >> 8) & 0xFF) / 255.0
        let b = CGFloat(hexInt & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
