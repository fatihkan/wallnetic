import SwiftUI
import UniformTypeIdentifiers

enum SidebarSelection: Hashable {
    case all
    case favorites
    case recent
    case aiGenerate
    case aiHistory
    case collections
    case collection(UUID)
}

struct ContentView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var selectedWallpaper: Wallpaper?
    @State private var isImporting = false
    @State private var searchText = ""
    @State private var sidebarSelection: SidebarSelection? = .all
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showingOnboarding = false

    var body: some View {
        NavigationSplitView {
            // Sidebar
            SidebarView(selection: $sidebarSelection)
        } detail: {
            // Main content based on sidebar selection
            switch sidebarSelection {
            case .aiGenerate:
                AIGenerateView()
            case .aiHistory:
                HistoryView()
            case .collections:
                CollectionsView()
            case .collection(let collectionId):
                CollectionDetailView(collectionId: collectionId)
            case .all, .favorites, .recent, .none:
                if wallpaperManager.wallpapers.isEmpty {
                    EmptyLibraryView(isImporting: $isImporting)
                } else {
                    WallpaperGridView(
                        selectedWallpaper: $selectedWallpaper,
                        searchText: searchText,
                        filter: sidebarSelection ?? .all
                    )
                }
            }
        }
        .navigationTitle("Wallnetic")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Search
                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                // AI Generate shortcut
                Button {
                    withAnimation { sidebarSelection = .aiGenerate }
                } label: {
                    Label("Generate", systemImage: "wand.and.stars")
                }
                .keyboardShortcut("g", modifiers: .command)

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
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView(isPresented: $showingOnboarding)
        }
        .onAppear {
            if !hasCompletedOnboarding {
                showingOnboarding = true
                hasCompletedOnboarding = true
            }
        }
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
    @ObservedObject var collectionManager = CollectionManager.shared
    @Binding var selection: SidebarSelection?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("Library") {
                    Label("All", systemImage: "photo.on.rectangle")
                        .tag(SidebarSelection.all)

                    Label("Favorites", systemImage: "heart")
                        .tag(SidebarSelection.favorites)

                    Label("Recent", systemImage: "clock")
                        .tag(SidebarSelection.recent)
                }

                Section("Collections") {
                    Label("All Collections", systemImage: "folder")
                        .tag(SidebarSelection.collections)

                    ForEach(collectionManager.collections) { collection in
                        Label(collection.name, systemImage: collection.icon)
                            .tag(SidebarSelection.collection(collection.id))
                    }
                }

                Section("AI") {
                    Label("Generate", systemImage: "wand.and.stars")
                        .tag(SidebarSelection.aiGenerate)

                    Label("History", systemImage: "clock.arrow.circlepath")
                        .tag(SidebarSelection.aiHistory)
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
            .animation(.easeInOut(duration: 0.2), value: selection)

        }
        .frame(minWidth: 180)
    }
}

// MARK: - Empty Library View

struct EmptyLibraryView: View {
    @Binding var isImporting: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [.purple.opacity(0.1), .blue.opacity(0.1)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 52))
                    .foregroundStyle(
                        LinearGradient(colors: [.purple, .blue],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }

            VStack(spacing: 8) {
                Text("No Wallpapers Yet")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Import video files to transform your desktop\nwith stunning live wallpapers")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            HStack(spacing: 16) {
                Button {
                    isImporting = true
                } label: {
                    Label("Import Videos", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            HStack(spacing: 4) {
                Image(systemName: "arrow.down.doc")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text("Or drag and drop video files here")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(WallpaperManager.shared)
}
