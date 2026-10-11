import SwiftUI

struct CalmPlaybackSettingsView: View {
    @ObservedObject var settings: CalmPlaybackSettings

    var body: some View {
        Section("Calm Mode") {
            Toggle("Hold wallpaper motion", isOn: Binding(
                get: { settings.state.isCalmEnabled }, set: { settings.setCalmEnabled($0) }))
            Text("Hold the current frame for focus or presentations. Turn off Calm Mode to restore prior playback. Manual pauses and other restrictions still apply. Calm Mode resets when Wallnetic quits.")
                .font(.caption).foregroundColor(.secondary)
            Text("Also available from the menu bar (⌘⇧M while Wallnetic is active) and Shortcuts on macOS 14 or later.")
                .font(.caption).foregroundColor(.secondary)
        }
        Section("Thermal-aware Playback") {
            Toggle("Pause wallpaper when the Mac gets hot", isOn: Binding(
                get: { settings.state.isThermalEnabled }, set: { settings.setThermalEnabled($0) }))
            Text("Pauses after sustained heat, or immediately at critical pressure. After a minute of cooling, prior playback resumes if no other pause condition remains. No additional permissions are needed.")
                .font(.caption).foregroundColor(.secondary)
            if settings.state.isThermallyPaused {
                Label("Holding motion while the Mac cools down", systemImage: "thermometer.medium")
                    .font(.caption)
            }
        }
    }
}
