import SwiftUI

struct TimeOfDaySettingsView: View {
    @ObservedObject private var manager: TimeOfDayManager
    @EnvironmentObject private var wallpapers: WallpaperManager

    init(manager: TimeOfDayManager = .shared) { self.manager = manager }

    var body: some View {
        DailyScheduleContent(manager: manager, wallpapers: wallpapers.wallpapers)
    }
}

struct DailyScheduleContent: View {
    @ObservedObject var manager: TimeOfDayManager
    let wallpapers: [Wallpaper]
    @State private var editing: DailyWallpaperRange?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Daily wallpaper schedule", isOn: Binding(
                    get: { manager.isEnabled }, set: { if $0 { manager.start() } else { manager.stop() } }))
                Text(manager.status).font(.caption).foregroundColor(.secondary)
                if manager.manualOverrideUntil != nil && manager.isEnabled {
                    Button("Resume schedule now") { manager.resumeNow() }
                }
                if let notice = manager.migrationNotice { Text(notice).font(.caption).foregroundColor(.orange) }
                if let error = manager.error {
                    HStack {
                        Text(error).font(.caption).foregroundColor(.orange)
                        Spacer()
                        Button("Dismiss") { manager.dismissError() }.controlSize(.small)
                    }
                }
                DailyScheduleTimeline(ranges: manager.ranges, activeID: manager.activeRangeID,
                                      edit: { editing = $0 }, commit: { _ = manager.save($0) })
                HStack {
                    Button("Add range…") {
                        editing = DailyWallpaperRange(name: "Custom range", startMinute: 9 * 60, endMinute: 10 * 60, wallpaperPath: "")
                    }
                    Spacer()
                    Text("Drag a bar or its handles · 5-minute steps").font(.caption2).foregroundColor(.secondary)
                }
                if manager.ranges.reduce(0, { $0 + $1.durationMinutes }) == 1440 {
                    Text("The day is full. Shorten or remove a range to make room for another.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Divider()
                Text("Gaps and missing wallpapers keep the current wallpaper. Ranges cannot overlap. Overnight ranges are supported.")
                    .font(.caption).foregroundColor(.secondary)
                Text("Uses local time on all displays. Enabling this turns off the playlist and takes priority over weather assignments. Manual choices, including Space recovery, hold for 30 minutes.")
                    .font(.caption).foregroundColor(.secondary)
            }.padding(20)
        }
        .sheet(item: $editing) { range in
            DailyRangeEditor(range: range, wallpapers: wallpapers,
                             save: { manager.save($0) ? nil : manager.error },
                             remove: manager.ranges.contains(where: { $0.id == range.id }) ? { manager.remove(range.id) } : nil)
        }
    }
}
