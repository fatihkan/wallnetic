import SwiftUI

struct CollectionsView: View {
    @ObservedObject private var collectionManager = CollectionManager.shared
    @State private var showingCreateSheet = false
    @State private var selectedCollection: WallpaperCollection?
    @State private var collectionToRename: WallpaperCollection?

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
                                    collectionToRename = collection
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
        .sheet(item: $collectionToRename) { collection in
            RenameCollectionSheet(collection: collection)
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

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        WallneticSheet(title: "New Collection", icon: selectedIcon, width: 380) {
            VStack(alignment: .leading, spacing: 14) {
                Text("ICON")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.35))

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(48)), count: 6), spacing: 6) {
                    ForEach(WallpaperCollection.availableIcons, id: \.self) { icon in
                        IconPickerCell(
                            icon: icon,
                            isSelected: selectedIcon == icon
                        ) { selectedIcon = icon }
                    }
                }

                Text("NAME")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.top, 4)

                WallneticTextField(
                    placeholder: "e.g. Cyberpunk Nights",
                    text: $name,
                    icon: "tag.fill"
                ) {
                    if !trimmedName.isEmpty {
                        _ = collectionManager.createCollection(name: trimmedName, icon: selectedIcon)
                        dismiss()
                    }
                }
            }
        } footer: {
            WallneticButton.cancel { dismiss() }
            Spacer()
            WallneticButton.primary("Create", icon: "plus", isEnabled: !trimmedName.isEmpty) {
                _ = collectionManager.createCollection(name: trimmedName, icon: selectedIcon)
                dismiss()
            }
        }
    }
}

private struct IconPickerCell: View {
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
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
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
