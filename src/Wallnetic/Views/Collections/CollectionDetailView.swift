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
                Text(wallpaper.name)
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

    var body: some View {
        VStack(spacing: 16) {
            Text("Rename Collection")
                .font(.headline)

            TextField("Collection name", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Save") {
                    collectionManager.renameCollection(collection, to: name)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            name = collection.name
        }
    }
}

// MARK: - Icon Picker Sheet

struct IconPickerSheet: View {
    let collection: WallpaperCollection
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var collectionManager = CollectionManager.shared

    @State private var selectedIcon: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Choose Icon")
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(44)), count: 5), spacing: 8) {
                ForEach(WallpaperCollection.availableIcons, id: \.self) { icon in
                    Button {
                        selectedIcon = icon
                    } label: {
                        Image(systemName: icon)
                            .font(.title2)
                            .frame(width: 40, height: 40)
                            .background(selectedIcon == icon ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Save") {
                    collectionManager.changeIcon(collection, to: selectedIcon)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            selectedIcon = collection.icon
        }
    }
}

// MARK: - Preview

#Preview {
    CollectionDetailView(collectionId: UUID())
        .environmentObject(WallpaperManager.shared)
}
