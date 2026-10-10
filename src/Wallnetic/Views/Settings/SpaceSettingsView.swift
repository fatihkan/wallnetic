import SwiftUI

/// Space recovery and system wallpaper sync use separate controls and storage.
struct SpaceSettingsView: View {
    @ObservedObject private var spaceManager = SpaceWallpaperManager.shared
    @ObservedObject private var syncManager = SystemWallpaperSync.shared
    @EnvironmentObject var wallpaperManager: WallpaperManager

    var body: some View {
        Form {
            SpaceRecoverySections(manager: spaceManager, wallpapers: wallpaperManager.wallpapers)
            Section("Lock Screen & Mission Control") {
                Toggle("Sync video frame to system wallpaper", isOn: $syncManager.isEnabled)
                    .onChange(of: syncManager.isEnabled) { enabled in
                        if enabled { syncManager.syncNow() } else { syncManager.restoreOriginals() }
                    }
                Text("macOS shows the system wallpaper on the lock screen, in Mission Control previews, and during Space transitions. Wallnetic keeps it in sync with a still frame of your current video. macOS doesn't allow apps to play video on the lock screen itself.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Injectable content for an isolated native preview, without real desktop writes.
struct SpaceRecoverySections: View {
    @ObservedObject var manager: SpaceWallpaperManager
    let wallpapers: [Wallpaper]
    @State private var editing: SpaceWallpaperSelection?
    @State private var confirmingNewList = false

    var body: some View {
        Group {
            Section("Virtual Desktops (Spaces)") {
                Toggle("Keep selections for Spaces", isOn: Binding(
                    get: { manager.isEnabled }, set: { if $0 { manager.start() } else { manager.stop() } }))
                Text("Automatic per-Space switching is unavailable because individual desktops cannot be reliably identified.")
                    .font(.caption).foregroundColor(.secondary)
                Text("Applying a saved choice sets the wallpaper on all displays and Spaces. It does not bind it to one desktop.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("Saved choices") {
                if let error = manager.error {
                    Text(error).font(.caption).foregroundColor(.orange)
                    if manager.hasUnreadableData {
                        Button("Start a new list…") { confirmingNewList = true }
                    } else {
                        Button("Dismiss") { manager.dismissError() }.controlSize(.small)
                    }
                }
                if manager.selections.isEmpty && !manager.hasUnreadableData {
                    Text("Save a wallpaper here or use “Save for Space Recovery” in its Library menu. Your media stays in Library.")
                        .font(.caption).foregroundColor(.secondary)
                } else if !manager.selections.isEmpty {
                    Text(manager.recoveryReason.rawValue).font(.caption).foregroundColor(.secondary)
                }
                ForEach(manager.selections) { selection in
                    selectionRow(selection)
                }
                Button("Add saved choice…") {
                    editing = SpaceWallpaperSelection(name: "", wallpaperPath: wallpapers.first?.url.path ?? "")
                }
                .disabled(manager.hasUnreadableData || manager.selections.count >= 500)
                Text("An enabled daily schedule or playlist holds a manual choice for 30 minutes, then resumes.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .sheet(item: $editing) { selection in
            SpaceSelectionEditor(selection: selection, wallpapers: wallpapers) {
                manager.save($0) ? nil : manager.error
            }
        }
        .alert("Start a new saved list?", isPresented: $confirmingNewList) {
            Button("Cancel", role: .cancel) {}
            Button("Start New List") { _ = manager.startNewList() }
        } message: {
            Text("The unreadable settings will be kept as a backup. Library media will stay unchanged.")
        }
    }

    private func selectionRow(_ selection: SpaceWallpaperSelection) -> some View {
        let wallpaper = manager.wallpaper(for: selection)
        return HStack(spacing: 10) {
            if let wallpaper {
                AsyncThumbnailView(wallpaper: wallpaper, size: CGSize(width: 48, height: 27))
                    .cornerRadius(4).accessibilityHidden(true)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .frame(width: 48, height: 27).foregroundColor(.secondary).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(selection.name).lineLimit(1)
                Text(wallpaper?.displayName ?? "Wallpaper missing · edit to replace")
                    .font(.caption).foregroundColor(wallpaper == nil ? .orange : .secondary).lineLimit(1)
                Text(manager.lastAppliedSelectionID == selection.id
                     ? "Applied manually · no desktop binding" : "Needs reassignment")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer(minLength: 4)
            Button("Apply") { _ = manager.applySelection(selection.id) }
                .disabled(!manager.isEnabled || wallpaper == nil || manager.hasUnreadableData)
                .accessibilityLabel("Apply \(selection.name) to all displays and Spaces")
                .help("Apply to all displays and Spaces")
            Button("Edit") { editing = selection }
                .accessibilityLabel("Edit \(selection.name)")
            Button { manager.remove(selection.id) } label: { Image(systemName: "minus.circle") }
                .accessibilityLabel("Remove saved choice \(selection.name)")
                .help("Remove this choice; keep its Library media")
        }
        .controlSize(.small)
        .padding(.vertical, 3)
    }
}

struct SpaceSelectionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: SpaceWallpaperSelection
    @State private var error: String?
    let wallpapers: [Wallpaper]
    let save: (SpaceWallpaperSelection) -> String?

    init(selection: SpaceWallpaperSelection, wallpapers: [Wallpaper],
         save: @escaping (SpaceWallpaperSelection) -> String?) {
        _selection = State(initialValue: selection)
        self.wallpapers = wallpapers
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Saved Space choice").font(.headline)
            Form {
                TextField("Name", text: $selection.name, prompt: Text("For example, Focus"))
                Picker("Wallpaper", selection: $selection.wallpaperPath) {
                    Text("Choose from Library…").tag("")
                    if !selection.wallpaperPath.isEmpty && !wallpapers.contains(where: { $0.url.path == selection.wallpaperPath }) {
                        Text("Missing: " + URL(fileURLWithPath: selection.wallpaperPath).lastPathComponent)
                            .tag(selection.wallpaperPath)
                    }
                    ForEach(wallpapers) { Text($0.displayName).tag($0.url.path) }
                }
            }
            Text("Name this choice to remember where you want to use it. Saving keeps the selection without applying it or identifying a desktop.")
                .font(.caption).foregroundColor(.secondary)
            if let error { Text(error).font(.caption).foregroundColor(.orange) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    error = save(selection)
                    if error == nil { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

// MARK: - Wallpaper Picker Popup

struct WallpaperPickerPopup: View {
    let title: String
    let onSelect: (Wallpaper) -> Void
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @Environment(\.dismiss) var dismiss

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()
            .background(.bar)

            Divider()

            // Grid
            if wallpaperManager.wallpapers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No wallpapers in library")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(wallpaperManager.wallpapers) { wallpaper in
                            PickerCard(wallpaper: wallpaper) {
                                onSelect(wallpaper)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 600, height: 450)
    }
}

// MARK: - Picker Card

private struct PickerCard: View {
    let wallpaper: Wallpaper
    let onTap: () -> Void
    @State private var thumbnail: NSImage?
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .aspectRatio(16/9, contentMode: .fit)
                        .overlay { ProgressView().scaleEffect(0.7) }
                }

                if isHovering {
                    Color.accentColor.opacity(0.3)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }
            }
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovering ? Color.accentColor : Color.clear, lineWidth: 2)
            )

            Text(wallpaper.displayName)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { isHovering = h } }
        .onTapGesture { onTap() }
        .task {
            thumbnail = await wallpaper.generateThumbnail(size: CGSize(width: 320, height: 180))
        }
    }
}
