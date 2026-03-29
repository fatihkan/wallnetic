import SwiftUI

/// Settings view for time-of-day wallpaper switching
struct TimeOfDaySettingsView: View {
    @ObservedObject private var todManager = TimeOfDayManager.shared
    @EnvironmentObject var wallpaperManager: WallpaperManager

    var body: some View {
        Form {
            Section {
                Toggle("Auto-switch wallpapers by time of day", isOn: $todManager.isEnabled)
                    .onChange(of: todManager.isEnabled) { enabled in
                        if enabled { todManager.start() } else { todManager.stop() }
                    }

                if todManager.isEnabled {
                    HStack(spacing: 6) {
                        Image(systemName: todManager.currentSlot.icon)
                            .foregroundColor(todManager.currentSlot.color)
                        Text("Current: \(todManager.currentSlot.rawValue)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if todManager.manualOverride {
                            Text("(paused - manual override)")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }

            if todManager.isEnabled {
                Section("Time Slots") {
                    ForEach(TimeOfDayManager.TimeSlot.allCases) { slot in
                        timeSlotRow(slot)
                    }
                }

                Section {
                    Text("Wallpapers automatically switch when the time enters a new slot. Manual changes pause auto-switch for 30 minutes.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func timeSlotRow(_ slot: TimeOfDayManager.TimeSlot) -> some View {
        HStack(spacing: 12) {
            // Icon + name
            Image(systemName: slot.icon)
                .foregroundColor(slot.color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(slot.rawValue)
                    .fontWeight(.medium)

                // Time picker
                HStack(spacing: 4) {
                    Text("Starts at")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("", selection: Binding(
                        get: { todManager.startHour(for: slot) },
                        set: { todManager.setStartHour($0, for: slot) }
                    )) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(String(format: "%02d:00", hour)).tag(hour)
                        }
                    }
                    .frame(width: 80)
                }
            }

            Spacer()

            // Wallpaper picker
            let path = todManager.wallpaperPath(for: slot)
            if !path.isEmpty,
               let wallpaper = wallpaperManager.wallpapers.first(where: { $0.url.path == path }) {
                HStack(spacing: 6) {
                    AsyncThumbnailView(wallpaper: wallpaper, size: CGSize(width: 40, height: 24))
                        .cornerRadius(4)

                    Text(wallpaper.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 80)
                }
            }

            // Choose button
            Menu {
                ForEach(wallpaperManager.wallpapers) { wallpaper in
                    Button(wallpaper.name) {
                        todManager.setWallpaperPath(wallpaper.url.path, for: slot)
                    }
                }

                Divider()

                Button("Clear") {
                    todManager.setWallpaperPath("", for: slot)
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)

            // Active indicator
            if todManager.currentSlot == slot {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.vertical, 4)
    }
}
