import SwiftUI

struct CollectionsView: View {
    @ObservedObject private var collectionManager = CollectionManager.shared
    @State private var showingCreateSheet = false
    @State private var selectedCollection: WallpaperCollection?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Collections")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    showingCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            if collectionManager.collections.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No Collections")
                        .font(.headline)

                    Text("Create collections to organize your wallpapers")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button("Create Collection") {
                        showingCreateSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Collections list
                List(selection: $selectedCollection) {
                    ForEach(collectionManager.collections) { collection in
                        CollectionRow(collection: collection)
                            .tag(collection)
                            .contextMenu {
                                Button("Rename") {
                                    // Implementation tracked in #181.
                                }

                                Button("Delete", role: .destructive) {
                                    collectionManager.deleteCollection(collection)
                                }
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateCollectionSheet()
        }
    }
}

// MARK: - Collection Row

struct CollectionRow: View {
    let collection: WallpaperCollection

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: collection.icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name)
                    .fontWeight(.medium)

                Text("\(collection.wallpaperCount) wallpapers")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Create Collection Sheet

struct CreateCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var collectionManager = CollectionManager.shared

    @State private var name = ""
    @State private var selectedIcon = "folder.fill"

    var body: some View {
        VStack(spacing: 20) {
            Text("New Collection")
                .font(.headline)

            // Icon selection
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

            // Name input
            TextField("Collection name", text: $name)
                .textFieldStyle(.roundedBorder)

            // Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Create") {
                    _ = collectionManager.createCollection(name: name, icon: selectedIcon)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

// MARK: - Add to Collection Popover

struct AddToCollectionPopover: View {
    let wallpaper: Wallpaper
    @ObservedObject private var collectionManager = CollectionManager.shared
    @State private var showingCreateSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add to Collection")
                .font(.headline)
                .padding(.bottom, 4)

            if collectionManager.collections.isEmpty {
                Text("No collections yet")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(collectionManager.collections) { collection in
                    Button {
                        if collection.contains(wallpaper) {
                            collectionManager.removeWallpaper(wallpaper, from: collection)
                        } else {
                            collectionManager.addWallpaper(wallpaper, to: collection)
                        }
                    } label: {
                        HStack {
                            Image(systemName: collection.icon)
                                .foregroundColor(.accentColor)

                            Text(collection.name)

                            Spacer()

                            if collection.contains(wallpaper) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            Button {
                showingCreateSheet = true
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("New Collection")
                }
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(width: 200)
        .sheet(isPresented: $showingCreateSheet) {
            CreateCollectionSheet()
        }
    }
}

// MARK: - Preview

#Preview {
    CollectionsView()
}
