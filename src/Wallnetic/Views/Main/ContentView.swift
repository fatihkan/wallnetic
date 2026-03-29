import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var selectedTab: NavigationTab = .home
    @State private var isImporting = false
    @State private var searchText = ""
    @State private var scrollOffset: CGFloat = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showingOnboarding = false

    var body: some View {
        ZStack(alignment: .top) {
            // Main content
            if wallpaperManager.wallpapers.isEmpty {
                // Dark background for empty state
                Color.black.ignoresSafeArea()
                EmptyLibraryView(isImporting: $isImporting)
            } else {
                // Tab content
                Group {
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

            // Floating Netflix-style header on top
            TopNavigationBar(
                selectedTab: $selectedTab,
                searchText: $searchText,
                isImporting: $isImporting,
                isScrolled: scrollOffset > 50
            )
        }
        .preferredColorScheme(.dark)
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

    // MARK: - Import

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
                    do { _ = try await wallpaperManager.importVideo(from: url) }
                    catch { print("Drop error: \(error)") }
                }
            }
        }
    }
}

// MARK: - Empty Library View

struct EmptyLibraryView: View {
    @Binding var isImporting: Bool

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(colors: [.red.opacity(0.15), .clear],
                                       center: .center, startRadius: 20, endRadius: 80)
                    )
                    .frame(width: 160, height: 160)

                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(
                        LinearGradient(colors: [.red, .red.opacity(0.7)],
                                       startPoint: .top, endPoint: .bottom)
                    )
            }

            VStack(spacing: 8) {
                Text("Welcome to Wallnetic")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Import video files to set as your live desktop wallpaper")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.5))
            }

            Button {
                isImporting = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                    Text("Import Videos")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(4)
            }
            .buttonStyle(.plain)

            Text("Drag and drop MP4, MOV, or M4V files")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.35))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
        .environmentObject(WallpaperManager.shared)
}
