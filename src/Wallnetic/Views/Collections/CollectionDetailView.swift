import SwiftUI

struct CollectionDetailView: View {
    let collectionId: UUID

    @ObservedObject private var collectionManager = CollectionManager.shared
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var selectedWallpaper: Wallpaper?
    @State private var showingRenameSheet = false
    @State private var showingIconPicker = false

    private var collection: WallpaperCollection? {
        collectionManager.collections.first { $0.id == collectionId }
    }

    private var wallpapers: [Wallpaper] {
        guard let collection = collection else { return [] }
        return collectionManager.wallpapers(in: collection)
    }

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            if let collection = collection {
                // Header
                HStack {
                    Image(systemName: collection.icon)
                        .font(.title)
                        .foregroundColor(.accentColor)

                    Text(collection.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Spacer()

                    Menu {
                        Button("Rename") {
                            showingRenameSheet = true
                        }

                        Button("Change Icon") {
                            showingIconPicker = true
                        }

                        Divider()

                        Button("Delete Collection", role: .destructive) {
                            collectionManager.deleteCollection(collection)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                }
                .padding()

                Divider()

                if wallpapers.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("No Wallpapers")
                            .font(.headline)

                        Text("Add wallpapers to this collection from the library")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Wallpaper grid
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(wallpapers) { wallpaper in
                                CollectionWallpaperCard(
                                    wallpaper: wallpaper,
                                    collection: collection,
                                    isSelected: selectedWallpaper?.id == wallpaper.id
                                )
                                .onTapGesture {
                                    selectedWallpaper = wallpaper
                                }
                                .onTapGesture(count: 2) {
                                    wallpaperManager.setWallpaper(wallpaper)
                                }
                            }
                        }
                        .padding()
                    }
                }
            } else {
                Text("Collection not found")
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showingRenameSheet) {
            if let collection = collection {
                RenameCollectionSheet(collection: collection)
            }
        }
        .sheet(isPresented: $showingIconPicker) {
            if let collection = collection {
                IconPickerSheet(collection: collection)
            }
        }
    }
}

// MARK: - Collection Wallpaper Card

struct CollectionWallpaperCard: View {
    let wallpaper: Wallpaper
    let collection: WallpaperCollection
    @ObservedObject private var collectionManager = CollectionManager.shared

    var isSelected: Bool = false
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 8) {
            // Thumbnail
            ZStack {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                        .frame(height: 120)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .aspectRatio(16/9, contentMode: .fill)
                        .frame(height: 120)
                        .overlay {
                            ProgressView()
                        }
                }

                // Remove button
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            collectionManager.removeWallpaper(wallpaper, from: collection)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(.white)
                                .shadow(radius: 2)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(8)
            }
            .cornerRadius(8)

            // Info
            VStack(spacing: 2) {
                Text(wallpaper.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(wallpaper.formattedResolution)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(12)
        .task {
            thumbnail = await wallpaper.generateThumbnail()
        }
    }
}

// MARK: - Rename Collection Sheet

struct RenameCollectionSheet: View {
    let collection: WallpaperCollection
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var collectionManager = CollectionManager.shared

    @State private var name: String = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canRename: Bool {
        !trimmedName.isEmpty && trimmedName != collection.name
    }

    var body: some View {
        WallneticSheet(title: "Rename Collection", icon: collection.icon, width: 380) {
            VStack(alignment: .leading, spacing: 10) {
                Text("NEW NAME")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.35))

                WallneticTextField(
                    placeholder: collection.name,
                    text: $name,
                    icon: "pencil"
                ) {
                    commit()
                }

                Text("Current: \(collection.name)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
            }
        } footer: {
            WallneticButton.cancel { dismiss() }
            Spacer()
            WallneticButton.primary("Save", icon: "checkmark", isEnabled: canRename) {
                commit()
            }
        }
        .onAppear { name = collection.name }
    }

    private func commit() {
        guard canRename else { return }
        collectionManager.renameCollection(collection, to: trimmedName)
        dismiss()
    }
}

// MARK: - Icon Picker Sheet

struct IconPickerSheet: View {
    let collection: WallpaperCollection
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var collectionManager = CollectionManager.shared

    @State private var selectedIcon: String = ""

    var body: some View {
        WallneticSheet(title: "Choose Icon", icon: selectedIcon.isEmpty ? "square.grid.2x2" : selectedIcon, width: 380) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(48)), count: 6), spacing: 6) {
                ForEach(WallpaperCollection.availableIcons, id: \.self) { icon in
                    IconCell(icon: icon, isSelected: selectedIcon == icon) {
                        selectedIcon = icon
                    }
                }
            }
        } footer: {
            WallneticButton.cancel { dismiss() }
            Spacer()
            WallneticButton.primary("Save", icon: "checkmark") {
                collectionManager.changeIcon(collection, to: selectedIcon)
                dismiss()
            }
        }
        .onAppear { selectedIcon = collection.icon }
    }
}

private struct IconCell: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(hover ? 0.8 : 0.45))
                .frame(width: 44, height: 44)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected
                                  ? AnyShapeStyle(LinearGradient(
                                        colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.15)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ))
                                  : AnyShapeStyle(Color.white.opacity(hover ? 0.06 : 0.025)))
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 0.5)
                    }
                )
                .shadow(color: isSelected ? Color.accentColor.opacity(0.4) : .clear, radius: 8)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

// MARK: - Preview

#Preview {
    CollectionDetailView(collectionId: UUID())
        .environmentObject(WallpaperManager.shared)
}
