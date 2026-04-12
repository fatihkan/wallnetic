import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }

            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            PlaybackSettingsView()
                .tabItem { Label("Playback", systemImage: "play.circle") }

            EffectsSettingsView()
                .tabItem { Label("Effects", systemImage: "wand.and.stars") }

            TimeOfDaySettingsView()
                .tabItem { Label("Schedule", systemImage: "clock.arrow.2.circlepath") }

            SpaceSettingsView()
                .tabItem { Label("Spaces", systemImage: "square.stack.3d.up") }

            DisplaySettingsView()
                .tabItem { Label("Display", systemImage: "display") }

            NotificationSettingsView()
                .tabItem { Label("Notifications", systemImage: "bell") }

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 680, height: 500)
    }
}

#Preview {
    SettingsView()
        .environmentObject(WallpaperManager.shared)
}
