import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var selectedTab: NavigationTab = .home
    @State private var isImporting = false
    @State private var searchText = ""
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showingOnboarding = false

    var body: some View {
        VStack(spacing: 0) {
            // Top navigation bar
            TopNavigationBar(
                selectedTab: $selectedTab,
                searchText: $searchText,
                isImporting: $isImporting
            )

            Divider()

            // Main content based on selected tab
            if wallpaperManager.wallpapers.isEmpty {
                EmptyLibraryView(isImporting: $isImporting)
            } else {
                switch selectedTab {
                case .home:
                    HomeView()
                case .explore:
                    ExploreView(searchText: searchText)
                case .popular:
                    PopularView()
                }
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
        .frame(minWidth: 900, minHeight: 600)
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

            Button {
                isImporting = true
            } label: {
                Label("Import Videos", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack(spacing: 4) {
                Image(systemName: "arrow.down.doc")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text("Or drag and drop video files here")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

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
