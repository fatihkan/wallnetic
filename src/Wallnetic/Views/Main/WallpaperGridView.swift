import SwiftUI

/// Grid filter mode
enum GridFilter: String {
    case all, favorites, recent
}

struct WallpaperGridView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @Binding var selectedWallpaper: Wallpaper?
    let searchText: String
    var filter: GridFilter = .all
    @State private var previewWallpaper: Wallpaper?
    @State private var renamingWallpaper: Wallpaper?
    @State private var renameText: String = ""

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 16)
    ]

    var filteredWallpapers: [Wallpaper] {
        var wallpapers = wallpaperManager.wallpapers

        switch filter {
        case .all:
            break
        case .favorites:
            wallpapers = wallpapers.filter { $0.isFavorite }
        case .recent:
            let oneWeekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            wallpapers = wallpapers
                .filter { $0.dateAdded > oneWeekAgo }
                .sorted { $0.dateAdded > $1.dateAdded }
        }

        if !searchText.isEmpty {
            wallpapers = wallpapers.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }

        return wallpapers
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(filteredWallpapers.enumerated()), id: \.element.id) { index, wallpaper in
                        WallpaperCard(
                            wallpaper: wallpaper,
                            isSelected: selectedWallpaper?.id == wallpaper.id
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedWallpaper = wallpaper
                            }
                        }
                        .onTapGesture(count: 2) {
                            wallpaperManager.setWallpaper(wallpaper)
                        }
                        .contextMenu {
                            WallpaperContextMenu(
                                wallpaper: wallpaper,
                                onPreview: {
                                    withAnimation { previewWallpaper = wallpaper }
                                },
                                onRename: {
                                    renameText = wallpaper.displayName
                                    renamingWallpaper = wallpaper
                                }
                            )
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
                .padding()
                .animation(.easeInOut(duration: 0.3), value: filteredWallpapers.map(\.id))
            }
            .background(Color(nsColor: .controlBackgroundColor))

            // Bottom bar with selected wallpaper info
            if let selected = selectedWallpaper {
                SelectedWallpaperBar(wallpaper: selected)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedWallpaper?.id)
        .overlay {
            if let preview = previewWallpaper {
                VideoPreviewView(
                    wallpaper: preview,
                    onApply: {
                        wallpaperManager.setWallpaper(preview)
                    },
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            previewWallpaper = nil
                        }
                    }
                )
                .transition(.opacity)
            }
        }
        .sheet(item: $renamingWallpaper) { wallpaper in
            RenameWallpaperSheet(
                wallpaper: wallpaper,
                title: $renameText,
                onSave: { newTitle in
                    wallpaperManager.renameWallpaper(wallpaper, to: newTitle)
                    renamingWallpaper = nil
                },
                onCancel: { renamingWallpaper = nil }
            )
        }
        .modifier(KeyPressModifier(
            onSpace: {
                if let selected = selectedWallpaper {
                    withAnimation(.easeIn(duration: 0.2)) { previewWallpaper = selected }
                }
            },
            onEscape: {
                if previewWallpaper != nil {
                    withAnimation(.easeOut(duration: 0.2)) { previewWallpaper = nil }
                }
            },
            onReturn: {
                if let preview = previewWallpaper {
                    wallpaperManager.setWallpaper(preview)
                    withAnimation { previewWallpaper = nil }
                } else if let selected = selectedWallpaper {
                    wallpaperManager.setWallpaper(selected)
                }
            }
        ))
    }
}

// MARK: - Wallpaper Card

struct WallpaperCard: View {
    let wallpaper: Wallpaper
    let isSelected: Bool
    @State private var thumbnail: NSImage?
    @State private var isHovering = false
    @State private var isFlipped = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail with flip
            ZStack {
                if !isFlipped {
                    // Front: thumbnail
                    frontView
                } else {
                    // Back: metadata
                    backView
                }
            }
            .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            .animation(Anim.gentle, value: isFlipped)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(wallpaper.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text("\(wallpaper.formattedResolution) • \(wallpaper.formattedFileSize)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .scaleEffect(isHovering ? 1.03 : 1.0)
        .shadow(color: .black.opacity(isHovering ? 0.2 : 0), radius: 8, y: 4)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovering = hovering
            }
            // Auto-unflip when mouse leaves
            if !hovering && isFlipped {
                withAnimation(Anim.gentle) { isFlipped = false }
            }
        }
        .task {
            thumbnail = await wallpaper.generateThumbnail()
        }
    }

    // MARK: - Front View

    private var frontView: some View {
        ZStack {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fill)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay { ProgressView() }
            }

            // Duration badge
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(wallpaper.formattedDuration)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial)
                        .cornerRadius(4)
                        .padding(8)
                }
            }

            // Hover overlay
            if isHovering {
                Color.black.opacity(0.3)

                HStack(spacing: 16) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white)

                    // Flip button
                    Button {
                        withAnimation(Anim.gentle) { isFlipped = true }
                    } label: {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Back View (metadata)

    private var backView: some View {
        ZStack {
            Rectangle()
                .fill(Color(white: 0.12))
                .aspectRatio(16/9, contentMode: .fit)

            VStack(alignment: .leading, spacing: 8) {
                Text(wallpaper.displayName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                Divider().background(.white.opacity(0.1))

                metadataRow("Resolution", value: wallpaper.formattedResolution)
                metadataRow("Duration", value: wallpaper.formattedDuration)
                metadataRow("File Size", value: wallpaper.formattedFileSize)
                metadataRow("Added", value: wallpaper.dateAdded.formatted(.dateTime.month().day().year()))

                if wallpaper.isFavorite {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.pink)
                        Text("Favorite")
                            .foregroundColor(.pink)
                    }
                    .font(.system(size: 10))
                }
            }
            .padding(12)
            .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

// MARK: - Context Menu

struct WallpaperContextMenu: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    let wallpaper: Wallpaper
    var onPreview: (() -> Void)? = nil
    var onRename: (() -> Void)? = nil

    var body: some View {
        Button {
            wallpaperManager.setWallpaper(wallpaper)
        } label: {
            Label("Set as Wallpaper", systemImage: "photo.on.rectangle")
        }

        if let onPreview = onPreview {
            Button {
                onPreview()
            } label: {
                Label("Preview", systemImage: "eye")
            }
        }

        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                wallpaperManager.toggleFavorite(wallpaper)
            }
        } label: {
            Label(
                wallpaper.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: wallpaper.isFavorite ? "heart.fill" : "heart"
            )
        }

        if let onRename = onRename {
            Button {
                onRename()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
        }

        Divider()

        // Lock screen option
        Button {
            LockScreenManager.shared.setLockScreenWallpaper(wallpaper)
        } label: {
            Label("Set as Lock Screen", systemImage: "lock.rectangle")
        }

        // Space assignment - auto-detect current space
        if SpaceWallpaperManager.shared.isEnabled {
            Button {
                let currentSpace = SpaceWallpaperManager.shared.currentSpaceIndex
                SpaceWallpaperManager.shared.setWallpaper(wallpaper, forSpace: currentSpace)
            } label: {
                Label("Set for This Space", systemImage: "square.stack.3d.up")
            }
        }

        Divider()

        Button {
            NSWorkspace.shared.activateFileViewerSelecting([wallpaper.url])
        } label: {
            Label("Show in Finder", systemImage: "folder")
        }

        Divider()

        Button(role: .destructive) {
            wallpaperManager.removeWallpaper(wallpaper)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - Selected Wallpaper Bar

struct SelectedWallpaperBar: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    let wallpaper: Wallpaper

    var body: some View {
        HStack {
            // Preview thumbnail
            AsyncThumbnailView(wallpaper: wallpaper, size: CGSize(width: 80, height: 45))
                .cornerRadius(4)

            VStack(alignment: .leading) {
                Text(wallpaper.displayName)
                    .fontWeight(.medium)
                Text("\(wallpaper.formattedResolution) • \(wallpaper.formattedDuration)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Apply button
            Button {
                wallpaperManager.setWallpaper(wallpaper)
            } label: {
                Text("Apply Wallpaper")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .background(.bar)
    }
}

// MARK: - Async Thumbnail View

struct AsyncThumbnailView: View {
    let wallpaper: Wallpaper
    let size: CGSize
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: size.width, height: size.height)
            }
        }
        .task {
            thumbnail = await wallpaper.generateThumbnail(size: size)
        }
    }
}

// MARK: - Key Press Modifier (macOS 13+ compatible)

struct KeyPressModifier: ViewModifier {
    var onSpace: (() -> Void)? = nil
    var onEscape: (() -> Void)? = nil
    var onReturn: (() -> Void)? = nil
    var onLeft: (() -> Void)? = nil
    var onRight: (() -> Void)? = nil
    var onUp: (() -> Void)? = nil
    var onDown: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .onKeyPress(.space) { onSpace?(); return onSpace != nil ? .handled : .ignored }
                .onKeyPress(.escape) { onEscape?(); return onEscape != nil ? .handled : .ignored }
                .onKeyPress(.return) { onReturn?(); return onReturn != nil ? .handled : .ignored }
                .onKeyPress(.leftArrow) { onLeft?(); return onLeft != nil ? .handled : .ignored }
                .onKeyPress(.rightArrow) { onRight?(); return onRight != nil ? .handled : .ignored }
                .onKeyPress(.upArrow) { onUp?(); return onUp != nil ? .handled : .ignored }
                .onKeyPress(.downArrow) { onDown?(); return onDown != nil ? .handled : .ignored }
                .onKeyPress(.delete) { onDelete?(); return onDelete != nil ? .handled : .ignored }
        } else {
            content
                .onExitCommand { onEscape?() }
        }
    }
}

// MARK: - Rename Wallpaper Sheet

struct RenameWallpaperSheet: View {
    let wallpaper: Wallpaper
    @Binding var title: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Rename Wallpaper")
                    .font(.headline)
                Spacer()
            }

            TextField("Wallpaper name", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onSave(title)
                    }
                }

            HStack {
                if wallpaper.customTitle != nil {
                    Button("Reset to Original") {
                        onSave("")
                    }
                    .foregroundColor(.secondary)
                }

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)

                Button("Save") {
                    onSave(title)
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
