import SwiftUI

struct DailyScheduleTimeline: View {
    let ranges: [DailyWallpaperRange]
    let activeID: UUID?
    let edit: (DailyWallpaperRange) -> Void
    let commit: (DailyWallpaperRange) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("24 hours").font(.caption).frame(width: 86, alignment: .leading)
                GeometryReader { geometry in
                    let width = max(1, geometry.size.width - 12)
                    ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                        Text(String(format: "%02d", hour)).font(.caption2).monospacedDigit()
                            .position(x: 6 + width * Double(hour) / 24, y: 8)
                    }
                }.frame(height: 16)
                Color.clear.frame(width: 14, height: 1)
            }.foregroundColor(.secondary)
            ForEach(ranges.sorted { $0.startMinute < $1.startMinute }) { range in
                DailyScheduleTimelineRow(range: range, active: activeID == range.id, edit: edit, commit: commit)
            }
        }
    }
}

private struct DailyScheduleTimelineRow: View {
    let range: DailyWallpaperRange
    let active: Bool
    let edit: (DailyWallpaperRange) -> Void
    let commit: (DailyWallpaperRange) -> Void
    @State private var draft: DailyWallpaperRange?

    var body: some View {
        HStack(spacing: 8) {
            Button { edit(range) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(range.name).lineLimit(1)
                    Text(DailyWallpaperRange.timeLabel((draft ?? range).startMinute) + "–" + DailyWallpaperRange.timeLabel((draft ?? range).endMinute))
                        .font(.system(size: 9)).monospacedDigit().foregroundColor(.secondary)
                }.frame(width: 86, alignment: .leading)
            }.buttonStyle(.plain).help("Edit range")
            GeometryReader { geometry in
                let width = max(1, geometry.size.width - 12)
                let shown = draft ?? range
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12))
                    ForEach(Array(shown.segments.enumerated()), id: \.offset) { _, segment in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(active ? Color.accentColor : Color.teal.opacity(0.65))
                            .frame(width: max(3, width * Double(segment.count) / 1440), height: 22)
                            .offset(x: 6 + width * Double(segment.lowerBound) / 1440)
                            .gesture(drag(width: width, edge: nil))
                    }
                    handle(at: shown.startMinute, width: width, edge: true)
                    handle(at: shown.endMinute, width: width, edge: false)
                }
            }.frame(height: 28)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(range.name), \(DailyWallpaperRange.timeLabel(range.startMinute)) to \(DailyWallpaperRange.timeLabel(range.endMinute))")
            .accessibilityAction(named: Text("Edit range")) { edit(range) }
            Button { edit(range) } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless).frame(width: 14).accessibilityLabel("Edit \(range.name)")
        }.font(.caption)
    }

    private func handle(at minute: Int, width: CGFloat, edge: Bool) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.primary.opacity(0.85)).frame(width: 6, height: 18)
            .frame(width: 12, height: 28)
            .contentShape(Rectangle())
            .offset(x: width * Double(minute) / 1440)
            .highPriorityGesture(drag(width: width, edge: edge))
            .help(edge ? "Drag start time" : "Drag end time")
    }

    private func drag(width: CGFloat, edge: Bool?) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in draft = adjusted(by: value.translation.width, width: width, edge: edge) }
            .onEnded { value in
                commit(adjusted(by: value.translation.width, width: width, edge: edge))
                draft = nil
            }
    }
    private func adjusted(by translation: CGFloat, width: CGFloat, edge: Bool?) -> DailyWallpaperRange {
        guard translation.isFinite, width > 0 else { return range }
        let delta = Int((min(1440, max(-1440, translation / width * 1440)) / 5).rounded()) * 5
        guard let edge else { return DailyWallpaperSchedule.moving(range, by: delta) }
        var result = range
        if edge { result.startMinute = min(1439, max(0, range.startMinute + delta)) }
        else { result.endMinute = min(1440, max(0, range.endMinute + delta)) }
        return result
    }
}

struct DailyRangeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var range: DailyWallpaperRange
    @State private var start: String
    @State private var end: String
    @State private var error: String?
    let wallpapers: [Wallpaper]
    let save: (DailyWallpaperRange) -> String?
    let remove: (() -> Void)?

    init(range: DailyWallpaperRange, wallpapers: [Wallpaper], save: @escaping (DailyWallpaperRange) -> String?, remove: (() -> Void)?) {
        _range = State(initialValue: range)
        _start = State(initialValue: DailyWallpaperRange.timeLabel(range.startMinute))
        _end = State(initialValue: DailyWallpaperRange.timeLabel(range.endMinute))
        self.wallpapers = wallpapers
        self.save = save
        self.remove = remove
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Daily time range").font(.headline)
            Form {
                TextField("Name", text: $range.name)
                TextField("Start (HH:mm)", text: $start)
                TextField("End (HH:mm)", text: $end)
                Picker("Wallpaper", selection: $range.wallpaperPath) {
                    Text("Unassigned — keep current").tag("")
                    if !range.wallpaperPath.isEmpty && !wallpapers.contains(where: { $0.url.path == range.wallpaperPath }) {
                        Text("Missing: " + URL(fileURLWithPath: range.wallpaperPath).lastPathComponent).tag(range.wallpaperPath)
                    }
                    ForEach(wallpapers) { Text($0.displayName).tag($0.url.path) }
                }
            }
            Text("An end time before the start crosses midnight. Use 00:00–24:00 for a full day.")
                .font(.caption).foregroundColor(.secondary)
            if let error { Text(error).font(.caption).foregroundColor(.orange) }
            HStack {
                if let remove { Button("Remove range", role: .destructive) { remove(); dismiss() } }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    guard let start = DailyWallpaperRange.parseTime(start),
                          let end = DailyWallpaperRange.parseTime(end, allowsEndOfDay: true) else {
                        error = WallpaperScheduleError.invalidRange.localizedDescription
                        return
                    }
                    range.startMinute = start
                    range.endMinute = end
                    range.name = range.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if range.name.isEmpty { range.name = "Custom range" }
                    error = save(range)
                    if error == nil { dismiss() }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 440)
    }
}
