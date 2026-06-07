import SwiftUI

/// Settings for per-Space wallpaper and system wallpaper sync
struct SpaceSettingsView: View {
    @ObservedObject private var spaceManager = SpaceWallpaperManager.shared
    @ObservedObject private var syncManager = SystemWallpaperSync.shared
    @ObservedObject private var aerialInjector = SystemAerialInjector.shared
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var showingPicker = false
    @State private var pickerTargetSpace: Int = 0
    @State private var aerialError: String?

    var body: some View {
        Form {
            // Per-Space Wallpapers
            Section("Virtual Desktops (Spaces)") {
                Toggle("Different wallpaper per Space", isOn: $spaceManager.isEnabled)
                    .onChange(of: spaceManager.isEnabled) { enabled in
                        if enabled { spaceManager.start() } else { spaceManager.stop() }
                    }

                if spaceManager.isEnabled {
                    Text("Right-click any wallpaper and select \"Set for This Space\" to assign it to your current desktop.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(0..<6, id: \.self) { spaceIndex in
                        spaceRow(spaceIndex)
                    }
                }
            }

            // Lock Screen & Mission Control
            Section("Lock Screen & Mission Control") {
                Toggle("Sync video frame to system wallpaper", isOn: $syncManager.isEnabled)
                    .onChange(of: syncManager.isEnabled) { enabled in
                        if enabled {
                            syncManager.syncNow()
                        } else {
                            syncManager.restoreOriginals()
                        }
                    }

                Text("macOS shows the system wallpaper on the lock screen, in Mission Control previews, and during Space transitions. Wallnetic keeps it in sync with a still frame of your current video.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Real video on the lock screen — registers the wallpaper as a
                // custom macOS aerial. Writes outside the sandbox container, so
                // it only appears in the direct-download build.
                if aerialInjector.isSupported {
                    Divider()

                    if aerialInjector.isActive {
                        HStack {
                            Label("Live video screen saver active", systemImage: "checkmark.seal.fill")
                                .foregroundColor(.green)
                            Spacer()
                            Button("Turn Off") { turnOffLockScreenVideo() }
                                .controlSize(.small)
                        }
                    } else {
                        Button {
                            setLockScreenVideo()
                        } label: {
                            Label("Play video as screen saver", systemImage: "play.rectangle.fill")
                        }
                        .disabled(aerialInjector.isBusy || wallpaperManager.currentWallpaper == nil)
                    }

                    if aerialInjector.isBusy {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.6)
                            Text("Preparing video…").font(.caption).foregroundColor(.secondary)
                        }
                    }

                    Text("Registers your wallpaper as a macOS aerial so the real video plays as the screen saver (when the Mac is idle) and on the login screen. The instant lock screen (⌃⌘Q) always shows a still frame — that's a macOS limitation, the same for Apple's own aerials. Direct-download build only.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let aerialError {
                        Text(aerialError).font(.caption).foregroundColor(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingPicker) {
            WallpaperPickerPopup(
                title: "Choose Wallpaper for Space \(pickerTargetSpace + 1)"
            ) { wallpaper in
                spaceManager.setWallpaper(wallpaper, forSpace: pickerTargetSpace)
                showingPicker = false
            }
            .environmentObject(wallpaperManager)
        }
    }

    // MARK: - Space Row

    private func spaceRow(_ index: Int) -> some View {
        HStack(spacing: 12) {
            // Space number
            Text("\(index + 1)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(index == spaceManager.currentSpaceIndex ? .white : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(
                        index == spaceManager.currentSpaceIndex
                            ? Color.accentColor
                            : Color.secondary.opacity(0.2)
                    )
                )

            // Wallpaper preview
            if let wp = spaceManager.wallpaper(forSpace: index) {
                AsyncThumbnailView(wallpaper: wp, size: CGSize(width: 48, height: 27))
                    .cornerRadius(4)

                Text(wp.name)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .leading)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 48, height: 27)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    )

                Text("Not set")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Choose button
            Button("Choose...") {
                pickerTargetSpace = index
                showingPicker = true
            }
            .controlSize(.small)

            // Clear button
            if spaceManager.wallpaper(forSpace: index) != nil {
                Button {
                    spaceManager.clearAssignment(forSpace: index)
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Live Lock Screen Video (direct-download build only)

    private func setLockScreenVideo() {
        guard let wallpaper = wallpaperManager.currentWallpaper else { return }
        aerialError = nil
        Task {
            do {
                try await aerialInjector.setLockScreenVideo(wallpaper.url)
            } catch {
                aerialError = error.localizedDescription
            }
        }
    }

    private func turnOffLockScreenVideo() {
        aerialError = nil
        do {
            try aerialInjector.restore()
        } catch {
            aerialError = error.localizedDescription
        }
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
