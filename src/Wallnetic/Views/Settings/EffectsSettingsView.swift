import SwiftUI

/// Settings view for wallpaper visual effects
struct EffectsSettingsView: View {
    @ObservedObject private var effects = WallpaperEffectsManager.shared

    var body: some View {
        Form {
            // Presets
            Section("Presets") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(WallpaperEffectsManager.presets) { preset in
                            presetButton(preset)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Adjustments
            Section("Adjustments") {
                sliderRow("Brightness", icon: "sun.max", value: $effects.brightness,
                          range: -0.5...0.5, defaultValue: 0)

                sliderRow("Contrast", icon: "circle.lefthalf.filled", value: $effects.contrast,
                          range: 0.5...2.0, defaultValue: 1.0)

                sliderRow("Saturation", icon: "paintpalette", value: $effects.saturation,
                          range: 0...2.0, defaultValue: 1.0)

                sliderRow("Blur", icon: "aqi.medium", value: $effects.blur,
                          range: 0...20, defaultValue: 0)
            }

            // Color Overlay
            Section("Color Overlay") {
                Toggle("Enable Tint", isOn: $effects.tintEnabled)

                if effects.tintEnabled {
                    ColorPicker("Tint Color", selection: tintColorBinding)

                    sliderRow("Opacity", icon: "drop.halffull", value: $effects.tintOpacity,
                              range: 0...0.8, defaultValue: 0.3)
                }
            }

            // Vignette
            Section("Vignette") {
                Toggle("Enable Vignette", isOn: $effects.vignetteEnabled)

                if effects.vignetteEnabled {
                    sliderRow("Intensity", icon: "circle.dashed", value: $effects.vignetteIntensity,
                              range: 0...2.0, defaultValue: 0.5)
                }
            }

            // Reset
            Section {
                HStack {
                    Spacer()
                    Button("Reset All Effects") {
                        effects.resetEffects()
                    }
                    .disabled(!effects.hasActiveEffects)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: effects.brightness) { _ in effects.notifyEffectsChanged() }
        .onChange(of: effects.contrast) { _ in effects.notifyEffectsChanged() }
        .onChange(of: effects.saturation) { _ in effects.notifyEffectsChanged() }
        .onChange(of: effects.blur) { _ in effects.notifyEffectsChanged() }
        .onChange(of: effects.tintEnabled) { _ in effects.notifyEffectsChanged() }
        .onChange(of: effects.tintOpacity) { _ in effects.notifyEffectsChanged() }
        .onChange(of: effects.vignetteEnabled) { _ in effects.notifyEffectsChanged() }
        .onChange(of: effects.vignetteIntensity) { _ in effects.notifyEffectsChanged() }
    }

    // MARK: - Components

    private func presetButton(_ preset: WallpaperEffectsManager.EffectPreset) -> some View {
        Button {
            effects.applyPreset(preset)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: preset.icon)
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(effects.activePreset == preset.id
                                  ? Color.accentColor.opacity(0.2)
                                  : Color.secondary.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(effects.activePreset == preset.id
                                    ? Color.accentColor : Color.clear, lineWidth: 2)
                    )

                Text(preset.name)
                    .font(.caption2)
                    .foregroundColor(effects.activePreset == preset.id ? .accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func sliderRow(_ title: String, icon: String, value: Binding<Double>,
                           range: ClosedRange<Double>, defaultValue: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)

            Text(title)
                .frame(width: 80, alignment: .leading)

            Slider(value: value, in: range)

            Text(String(format: "%.1f", value.wrappedValue))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 32)

            Button {
                withAnimation { value.wrappedValue = defaultValue }
                effects.notifyEffectsChanged()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(value.wrappedValue != defaultValue ? 1 : 0.3)
        }
    }

    // MARK: - Color Binding

    private var tintColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: effects.tintColor) },
            set: { newColor in
                if let components = NSColor(newColor).usingColorSpace(.sRGB) {
                    let hex = String(format: "#%02X%02X%02X",
                                    Int(components.redComponent * 255),
                                    Int(components.greenComponent * 255),
                                    Int(components.blueComponent * 255))
                    effects.tintColorHex = hex
                    effects.notifyEffectsChanged()
                }
            }
        )
    }
}
