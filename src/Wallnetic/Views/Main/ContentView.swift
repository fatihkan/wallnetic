import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var selectedWallpaper: Wallpaper?
    @State private var isImporting = false
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            // Sidebar
            SidebarView(selectedWallpaper: $selectedWallpaper)
        } detail: {
            // Main content
            if wallpaperManager.wallpapers.isEmpty {
                EmptyLibraryView(isImporting: $isImporting)
            } else {
                WallpaperGridView(
                    selectedWallpaper: $selectedWallpaper,
                    searchText: searchText
                )
            }
        }
        .navigationTitle("Wallnetic")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Search
                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                // Import button
                Button {
                    isImporting = true
                } label: {
                    Label("Import", systemImage: "plus")
                }
                .keyboardShortcut("i", modifiers: .command)
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
            return true
        }
        .frame(minWidth: 800, minHeight: 500)
    }

    // MARK: - Import Handling

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                for url in urls {
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        do {
                            _ = try await wallpaperManager.importVideo(from: url)
                        } catch {
                            print("Import error: \(error)")
                        }
                    }
                }
            }
        case .failure(let error):
            print("File picker error: \(error)")
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                Task {
                    do {
                        _ = try await wallpaperManager.importVideo(from: url)
                    } catch {
                        print("Drop import error: \(error)")
                    }
                }
            }
        }
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @Binding var selectedWallpaper: Wallpaper?

    var body: some View {
        List {
            Section("Library") {
                NavigationLink {
                    Text("All Wallpapers")
                } label: {
                    Label("All", systemImage: "photo.on.rectangle")
                }

                NavigationLink {
                    Text("Favorites")
                } label: {
                    Label("Favorites", systemImage: "heart")
                }

                NavigationLink {
                    Text("Recent")
                } label: {
                    Label("Recent", systemImage: "clock")
                }
            }

            Section("Info") {
                HStack {
                    Text("Wallpapers")
                    Spacer()
                    Text("\(wallpaperManager.wallpapers.count)")
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180)
    }
}

// MARK: - Empty Library View

struct EmptyLibraryView: View {
    @Binding var isImporting: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("No Wallpapers")
                .font(.title2)
                .fontWeight(.medium)

            Text("Import video files to use as live wallpapers")
                .foregroundColor(.secondary)

            Button("Import Videos") {
                isImporting = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Or drag and drop video files here")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(WallpaperManager.shared)
}
