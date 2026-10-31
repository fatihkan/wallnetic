import SwiftUI

struct PauseAfterSettingsView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @ObservedObject private var settings = PauseAfterSettings.shared
    @State private var selectedPath = ""

    var body: some View {
        Section("Pause After") {
            PauseAfterDurationPicker(title: "Default interval", allowsInherit: false, seconds: Binding(
                get: { settings.preferences.defaultSeconds },
                set: { settings.setDefault(seconds: $0 ?? 0) }
            ))
            Picker("Wallpaper override", selection: $selectedPath) {
                Text("Choose a wallpaper…").tag("")
                ForEach(wallpaperManager.wallpapers) { wallpaper in
                    Text(wallpaper.displayName).tag(wallpaper.url.standardizedFileURL.path)
                }
            }
            if let wallpaper = wallpaperManager.wallpapers.first(where: { $0.url.standardizedFileURL.path == selectedPath }) {
                PauseAfterDurationPicker(title: "This wallpaper", allowsInherit: true, seconds: Binding(
                    get: { settings.preferences.overrides[selectedPath] },
                    set: { settings.setOverride(seconds: $0, for: wallpaper.url) }
                ))
                .id(selectedPath)
            }
            Text("Use Default follows the global interval. Never Pause keeps this wallpaper moving regardless of the default.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Replay when the desktop becomes clear", isOn: Binding(
                get: { settings.preferences.replayWhenDesktopClears },
                set: { settings.setReplayWhenDesktopClears($0) }
            ))
            .help("After regular app windows cover and then clear a display, replay its timed-out wallpaper once. Detection takes a few seconds.")
            Text("The last frame stays visible when time runs out. Play, a wallpaper change, or an allowed resume after unlock starts a new interval. Manual Pause stays paused until you press Play.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct PauseAfterDurationPicker: View {
    let title: String
    let allowsInherit: Bool
    @Binding var seconds: Int?
    @State private var customSelected = false

    private var selection: Binding<String> {
        Binding(get: {
            if seconds == nil { return "inherit" }
            if seconds == 0 { return "never" }
            if customSelected { return "custom" }
            if let seconds, PauseAfterSettings.presets.contains(seconds) { return String(seconds) }
            return "custom"
        }, set: { value in
            customSelected = value == "custom"
            switch value {
            case "inherit": seconds = nil
            case "never": seconds = 0
            case "custom": seconds = max(1, seconds ?? 60)
            default: seconds = Int(value) ?? 0
            }
        })
    }

    var body: some View {
        Picker(title, selection: selection) {
            if allowsInherit { Text("Use Default").tag("inherit") }
            Text("Never Pause").tag("never")
            ForEach(PauseAfterSettings.presets, id: \.self) { value in
                Text(value < 60 ? "\(value) seconds" : "\(value / 60) min").tag(String(value))
            }
            Text("Custom…").tag("custom")
        }
        if selection.wrappedValue == "custom" {
            TextField("Duration in seconds (1–86,400)", value: Binding(
                get: { seconds ?? 60 },
                set: { seconds = min(PauseAfterSettings.maximumSeconds, max(1, $0)) }
            ), format: .number)
        }
    }
}
