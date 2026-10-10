import SwiftUI

struct PlaylistSettingsView: View {
    @ObservedObject private var playlist = PlaylistManager.shared
    @ObservedObject private var collectionManager = CollectionManager.shared
    @EnvironmentObject private var wallpaperManager: WallpaperManager

    var body: some View {
        PlaylistScheduleContent(playlist: playlist, wallpapers: wallpaperManager.wallpapers,
                                collections: collectionManager.collections)
    }
}

struct PlaylistScheduleContent: View {
    @ObservedObject var playlist: PlaylistManager
    let wallpapers: [Wallpaper]
    let collections: [WallpaperCollection]
    @State private var editing: TimedWallpaperItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Automatically rotate wallpapers", isOn: Binding(
                    get: { playlist.isEnabled }, set: { if $0 { playlist.start() } else { playlist.stop() } }))
                Text(playlist.status).font(.caption).foregroundColor(.secondary)
                if playlist.manualOverrideUntil != nil && playlist.isEnabled {
                    Button("Resume playlist now") { playlist.resumeNow() }
                }
                if let error = playlist.error {
                    HStack {
                        Text(error).font(.caption).foregroundColor(.orange)
                        Spacer()
                        Button("Dismiss") { playlist.dismissError() }.controlSize(.small)
                    }
                }
                Toggle("Set a duration for each item", isOn: Binding(
                    get: { playlist.usesItemDurations }, set: { _ = playlist.setUsesItemDurations($0) }))
                if playlist.usesItemDurations {
                    Text("Plays in the order below, then repeats. Missing items are skipped.")
                        .font(.caption).foregroundColor(.secondary)
                    if playlist.items.isEmpty {
                        Text("Add wallpapers to build your playlist.").foregroundColor(.secondary)
                    }
                    ForEach(Array(playlist.items.enumerated()), id: \.element.id) { index, item in
                        itemRow(item, index: index)
                    }
                    Button("Add wallpaper…") {
                        let first = wallpapers.first
                        editing = TimedWallpaperItem(name: first?.displayName ?? "Wallpaper",
                            wallpaperPath: first?.url.path ?? "", durationSeconds: playlist.intervalSeconds)
                    }.disabled(playlist.items.count >= 500)
                } else {
                    Form {
                        Picker("Source", selection: $playlist.sourceRaw) {
                            ForEach(PlaylistManager.Source.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                        if playlist.source == .collection {
                            Picker("Collection", selection: $playlist.collectionIDString) {
                                Text("Choose…").tag("")
                                ForEach(collections) { Text($0.name).tag($0.id.uuidString) }
                            }
                            if collections.isEmpty { Text("Create a collection from a wallpaper's context menu first.").font(.caption) }
                        }
                        Picker("Order", selection: $playlist.orderRaw) {
                            ForEach(PlaylistManager.Order.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                        Picker("Change every", selection: $playlist.intervalSeconds) {
                            ForEach(Array(Set(PlaylistManager.intervalOptions + [playlist.intervalSeconds])).sorted(), id: \.self) {
                                Text(PlaylistManager.intervalLabel($0)).tag($0)
                            }
                        }
                    }
                }
                Divider()
                Text("Elapsed time includes sleep and time while the app is closed. On return, the playlist picks the current item. Editing the playlist starts a new cycle.")
                    .font(.caption).foregroundColor(.secondary)
                Text("Applies to all displays. Enabling this turns off the daily schedule and takes priority over weather assignments. Manual choices, including Space recovery, hold for 30 minutes.")
                    .font(.caption).foregroundColor(.secondary)
            }.padding(20)
        }
        .sheet(item: $editing) { item in
            TimedWallpaperEditor(item: item, wallpapers: wallpapers,
                                 save: { playlist.save($0) ? nil : playlist.error })
        }
    }

    private func itemRow(_ item: TimedWallpaperItem, index: Int) -> some View {
        let available = wallpapers.contains { $0.url.path == item.wallpaperPath && FileManager.default.fileExists(atPath: $0.url.path) }
        return HStack(spacing: 10) {
            Image(systemName: playlist.activeItemID == item.id ? "play.circle.fill" : "photo")
                .foregroundColor(playlist.activeItemID == item.id ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).lineLimit(1)
                Text(available ? "\(item.durationSeconds) seconds" : "Missing or unassigned · skipped")
                    .font(.caption).foregroundColor(available ? .secondary : .orange)
            }
            Spacer()
            Button { playlist.move(item.id, by: -1) } label: { Image(systemName: "arrow.up") }
                .disabled(index == 0).accessibilityLabel("Move \(item.name) up")
            Button { playlist.move(item.id, by: 1) } label: { Image(systemName: "arrow.down") }
                .disabled(index == playlist.items.count - 1).accessibilityLabel("Move \(item.name) down")
            Button("Edit") { editing = item }
            Button { playlist.remove(item.id) } label: { Image(systemName: "minus.circle") }
                .accessibilityLabel("Remove \(item.name) from playlist")
        }.buttonStyle(.borderless).padding(10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct TimedWallpaperEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var item: TimedWallpaperItem
    @State private var duration: String
    @State private var error: String?
    let wallpapers: [Wallpaper]
    let save: (TimedWallpaperItem) -> String?

    init(item: TimedWallpaperItem, wallpapers: [Wallpaper], save: @escaping (TimedWallpaperItem) -> String?) {
        _item = State(initialValue: item)
        _duration = State(initialValue: String(item.durationSeconds))
        self.wallpapers = wallpapers
        self.save = save
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Playlist item").font(.headline)
            Form {
                Picker("Wallpaper", selection: $item.wallpaperPath) {
                    Text("Unassigned — skipped").tag("")
                    if !item.wallpaperPath.isEmpty && !wallpapers.contains(where: { $0.url.path == item.wallpaperPath }) {
                        Text("Missing: " + item.name).tag(item.wallpaperPath)
                    }
                    ForEach(wallpapers) { Text($0.displayName).tag($0.url.path) }
                }
                TextField("Duration (seconds)", text: $duration)
            }
            Text("Use 1–86,400 seconds (up to 24 hours). The video loops for this duration.")
                .font(.caption).foregroundColor(.secondary)
            if let error { Text(error).font(.caption).foregroundColor(.orange) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    guard let seconds = Int(duration), (1...86400).contains(seconds) else {
                        error = WallpaperScheduleError.invalidDuration.localizedDescription
                        return
                    }
                    item.durationSeconds = seconds
                    if let wallpaper = wallpapers.first(where: { $0.url.path == item.wallpaperPath }) { item.name = wallpaper.displayName }
                    error = save(item)
                    if error == nil { dismiss() }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 440)
    }
}
