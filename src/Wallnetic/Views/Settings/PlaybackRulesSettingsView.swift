import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings > Playback > Playback Rules (#350). Every rule is off by
/// default; a rule that applies pauses playback without changing the user's
/// own Play or Pause.
struct PlaybackRulesSettingsView: View {
    @ObservedObject var settings: PlaybackRulesSettings
    @State private var displayCount = NSScreen.screens.count

    private var rules: PlaybackRulesConfiguration { settings.rules }

    private func binding<T>(_ keyPath: WritableKeyPath<PlaybackRulesConfiguration, T>) -> Binding<T> {
        Binding(get: { settings.rules[keyPath: keyPath] },
                set: { value in settings.update { $0[keyPath: keyPath] = value } })
    }

    var body: some View {
        Section {
            Toggle("Pause while chosen apps are in front", isOn: binding(\.pausesForFrontApps))
            if rules.pausesForFrontApps {
                PlaybackRuleAppList(apps: binding(\.frontApps), emptyText: String(localized: "No apps chosen. The rule does nothing yet."))
            }

            Toggle("Pause while chosen apps are running", isOn: binding(\.pausesForRunningApps))
            if rules.pausesForRunningApps {
                PlaybackRuleAppList(apps: binding(\.runningApps), emptyText: String(localized: "No apps chosen. The rule does nothing yet."))
            }

            Toggle("Pause when the Mac is idle", isOn: binding(\.pausesWhenIdle))
            if rules.pausesWhenIdle {
                Picker("After", selection: binding(\.idleMinutes)) {
                    ForEach(PlaybackRulesConfiguration.idleMinuteChoices, id: \.self) { minutes in
                        Text(minutes == 1 ? "1 minute" : "\(minutes) minutes").tag(minutes)
                    }
                }
                .help("Counted from the last key press, click or pointer movement. Playback continues at the next one.")
            }

            Toggle("Pause on low battery", isOn: binding(\.pausesOnLowBattery))
            if rules.pausesOnLowBattery {
                Picker("Below", selection: binding(\.lowBatteryPercent)) {
                    ForEach(PlaybackRulesConfiguration.batteryPercentChoices, id: \.self) { percent in
                        Text("\(percent)%").tag(percent)
                    }
                }
                .help("Applies on battery power only. Playback continues when the Mac is plugged in or charges above this level.")
            }

            Toggle("Play only on the display in use", isOn: binding(\.playsOnlyOnDisplayInUse))
                .help("With several displays, the wallpaper keeps moving where the pointer or the active window is, and pauses on the others a few seconds after you leave them.")
            if rules.playsOnlyOnDisplayInUse && displayCount < 2 {
                Text("This applies when more than one display is connected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Playback Rules")
        } footer: {
            Text("A rule pauses playback while its condition lasts and lets it continue afterwards. It never undoes your own Pause. The menu bar shows which rule is pausing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displayCount = NSScreen.screens.count
        }
    }
}

/// The apps of one rule: a row per app with a remove button, and Add App…
private struct PlaybackRuleAppList: View {
    @Binding var apps: [PlaybackRuleApp]
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if apps.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(apps) { app in
                HStack(spacing: 8) {
                    Image(nsImage: Self.icon(for: app))
                        .resizable()
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                    Text(app.name)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        apps.removeAll { $0.bundleID == app.bundleID }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove \(app.name)")
                    .accessibilityLabel("Remove \(app.name)")
                }
            }
            Button("Add App…") { chooseApps() }
                .controlSize(.small)
        }
        .padding(.leading, 20)
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose Apps")
        panel.prompt = String(localized: "Add")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK else { return }
        apps = PlaybackRulesSettings.adding(panel.urls.compactMap(Self.app(at:)), to: apps)
    }

    /// The bundle identifier and display name of an app bundle.
    static func app(at url: URL) -> PlaybackRuleApp? {
        guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
        return PlaybackRuleApp(bundleID: bundleID, name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name)
    }

    private static func icon(for app: PlaybackRuleApp) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }
}
