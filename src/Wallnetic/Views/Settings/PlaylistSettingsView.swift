import SwiftUI

/// Settings view for the auto-rotating wallpaper playlist (v1.4 Wave 1).
struct PlaylistSettingsView: View {
    @ObservedObject private var playlist = PlaylistManager.shared
    @ObservedObject private var collectionManager = CollectionManager.shared
    @EnvironmentObject var wallpaperManager: WallpaperManager

    var body: some View {
        Form {
            Section {
                Toggle("Automatically rotate wallpapers", isOn: $playlist.isEnabled)
                    .onChange(of: playlist.isEnabled) { enabled in
                        if enabled { playlist.enableExclusively() } else { playlist.stop() }
                    }

                if playlist.isEnabled {
                    Picker("Source", selection: $playlist.sourceRaw) {
                        ForEach(PlaylistManager.Source.allCases) { source in
                            Text(source.label).tag(source.rawValue)
                        }
                    }

                    if playlist.source == .collection {
                        collectionPicker
                    }

                    Picker("Order", selection: $playlist.orderRaw) {
                        ForEach(PlaylistManager.Order.allCases) { order in
                            Text(order.label).tag(order.rawValue)
                        }
                    }

                    Picker("Change every", selection: $playlist.intervalSeconds) {
                        ForEach(PlaylistManager.intervalOptions, id: \.self) { seconds in
                            Text(PlaylistManager.intervalLabel(seconds)).tag(seconds)
                        }
                    }
                    .onChange(of: playlist.intervalSeconds) { _ in
                        playlist.reschedule()
                    }
                }
            }

            if playlist.isEnabled {
                Section {
                    Text("Wallpapers rotate on the chosen interval. Turning this on disables time-of-day switching, and vice versa.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var collectionPicker: some View {
        if collectionManager.collections.isEmpty {
            Text("No collections yet — create one from a wallpaper's context menu first.")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            Picker("Collection", selection: $playlist.collectionIDString) {
                Text("Choose…").tag("")
                ForEach(collectionManager.collections) { collection in
                    Text(collection.name).tag(collection.id.uuidString)
                }
            }
        }
    }
}
