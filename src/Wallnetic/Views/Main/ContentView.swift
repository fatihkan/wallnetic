import SwiftUI
import UniformTypeIdentifiers

enum SidebarSelection: Hashable {
    case all
    case favorites
    case recent
    case aiGenerate
    case aiHistory
}

struct ContentView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var selectedWallpaper: Wallpaper?
    @State private var isImporting = false
    @State private var searchText = ""
    @State private var sidebarSelection: SidebarSelection? = .all

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
    @ObservedObject var scheduler = SchedulerService.shared
    @Binding var selection: SidebarSelection?
    @State private var showingSchedulerSettings = false

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                Label("All", systemImage: "photo.on.rectangle")
                    .tag(SidebarSelection.all)

                Label("Favorites", systemImage: "heart")
                    .tag(SidebarSelection.favorites)

                Label("Recent", systemImage: "clock")
                    .tag(SidebarSelection.recent)
            }

            Section("AI") {
                Label("Generate", systemImage: "wand.and.stars")
                    .tag(SidebarSelection.aiGenerate)

                Label("History", systemImage: "clock.arrow.circlepath")
                    .tag(SidebarSelection.aiHistory)
            }

            Section("Scheduler") {
                Button {
                    showingSchedulerSettings = true
                } label: {
                    HStack {
                        Label("Daily Wallpaper", systemImage: scheduler.isEnabled ? "clock.badge.checkmark" : "clock")
                            .foregroundColor(scheduler.isEnabled ? .accentColor : .primary)

                        Spacer()

                        if scheduler.isEnabled {
                            Text(scheduler.formattedScheduleTime)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)

                if scheduler.isEnabled {
                    if scheduler.isGenerating {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Generating...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if let nextTime = scheduler.formattedNextScheduledTime {
                        Text("Next: \(nextTime)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
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
        .sheet(isPresented: $showingSchedulerSettings) {
            SchedulerSettingsView()
        }
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
