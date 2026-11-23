import SwiftUI
import AppKit

/// The Settings window: a standard sidebar and one page per section
/// (#343 B3b). The sidebar is the system's, so it is Liquid Glass on
/// macOS 26 and a regular sidebar on earlier systems.
struct SettingsView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    /// Optional because a sidebar list can have no selection; the detail
    /// then falls back to General.
    @State private var selection: SettingsSection? = .general

    private var current: SettingsSection { selection ?? .general }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            content
                // A split view sizes itself by its detail's minimum height.
                // A page that is not a scroll view (Storage) reports a very
                // tall one when probed at zero width, which pushed the whole
                // window's content out of view. Pages take the space given.
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
                // The pages are grouped forms. They sit on the window's own
                // floor instead of the form's default backdrop.
                .scrollContentBackground(.hidden)
                // A page that scrolls gets the system's title bar backdrop
                // once content moves under it; without one, the content
                // showed through the title. A page that does not scroll
                // would show that backdrop all the time, so it has none.
                .toolbarBackground(current.scrolls ? .automatic : .hidden, for: .windowToolbar)
                .navigationTitle(current.title)
                .navigationSubtitle(current.tagline)
        }
        .frame(width: 820, height: 540)
        .preferredColorScheme(themeManager.appearanceMode.swiftUIColorScheme)
        .onAppear {
            // #228: ensure the app is active/regular so this window can become
            // key and its controls render — covers every open path (⌘,, the nav
            // gear, the in-window banner, the menu-bar item), incl. accessory
            // mode under "Hide Dock icon". DockIconPolicy re-hides on close.
            if NSApp.activationPolicy() == .accessory {
                NSApp.setActivationPolicy(.regular)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                ForEach(SettingsSection.allCases.filter { !$0.isFooter }) { section in
                    Label(section.title, systemImage: section.icon).tag(section)
                }
            }
            Section {
                ForEach(SettingsSection.allCases.filter { $0.isFooter }) { section in
                    Label(section.title, systemImage: section.icon).tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(220)
        .modifier(FixedSidebar())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.xs)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var content: some View {
        switch current {
        case .general:    GeneralSettingsView()
        case .storage:    StorageSettingsView()
        case .appearance: AppearanceSettingsView()
        case .playback:   PlaybackSettingsView()
        case .effects:    EffectsSettingsView()
        case .schedule:   TimeOfDaySettingsView()
        case .playlist:   PlaylistSettingsView()
        case .spaces:     SpaceSettingsView()
        case .display:    DisplaySettingsView()
        case .about:      AboutSettingsView()
        }
    }
}

/// Settings always shows its sidebar, so the button that hides it is
/// removed where the system allows (macOS 14 and later).
private struct FixedSidebar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            content
        }
    }
}

// MARK: - Sections

private enum SettingsSection: String, CaseIterable, Identifiable {
    // smartTags (Ollama Vision auto-tagging) gizlendi — App Store
    // submission disinda tutuluyor. View + service kodu intact;
    // case'i geri eklemek yeterli.
    // notifications da ayni sekilde gizlendi (#312): bu surumde bildirim
    // gonderen bir ozellik yok, sayfa yalnizca izin istiyordu.
    case general, storage, appearance, playback, effects, schedule, playlist, spaces, display, about

    var id: String { rawValue }
    var isFooter: Bool { self == .about }
    /// Whether the page's root is a scroll view. Storage and About are not.
    var scrolls: Bool { self != .storage && self != .about }

    var title: String {
        switch self {
        case .general:       return String(localized: "General")
        case .storage:       return String(localized: "Storage")
        case .appearance:    return String(localized: "Appearance")
        case .playback:      return String(localized: "Playback")
        case .effects:       return String(localized: "Effects")
        case .schedule:      return String(localized: "Schedule")
        case .playlist:      return String(localized: "Playlist")
        case .spaces:        return String(localized: "Spaces")
        case .display:       return String(localized: "Display")
        case .about:         return String(localized: "About")
        }
    }

    var tagline: String {
        switch self {
        case .general:       return String(localized: "App-wide behavior and library location.")
        case .storage:       return String(localized: "Library sizes and safe cleanup.")
        case .appearance:    return String(localized: "Theme, accent, and dynamic colors.")
        case .playback:      return String(localized: "Power, performance, and pause rules.")
        case .effects:       return String(localized: "Live wallpaper post-processing.")
        case .schedule:      return String(localized: "Custom daily time ranges.")
        case .playlist:      return String(localized: "Rotate with individual durations.")
        case .spaces:        return String(localized: "Saved choices and desktop recovery.")
        case .display:       return String(localized: "Per-monitor mode and tracking.")
        case .about:         return String(localized: "Version, credits, and links.")
        }
    }

    var icon: String {
        switch self {
        case .general:       return "gear"
        case .storage:       return "externaldrive"
        case .appearance:    return "paintbrush"
        case .playback:      return "play"
        case .effects:       return "wand.and.stars"
        case .schedule:      return "clock.arrow.2.circlepath"
        case .playlist:      return "shuffle"
        case .spaces:        return "square.stack.3d.up"
        case .display:       return "display"
        case .about:         return "info.circle"
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(WallpaperManager.shared)
}
