import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var errorReporter = ErrorReporter.shared
    @State private var selectedTab: NavigationTab = .home
    @State private var isImporting = false
    @State private var showingPhotosImport = false
    @State private var searchText = ""
    @State private var scrollOffset: CGFloat = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showingOnboarding = false
    @State private var importError: String?

    var body: some View {
        ZStack {
            // Animated gradient background
            AnimatedGradientBackground()

            VStack(spacing: 0) {
                TopNavigationBar(
                    selectedTab: $selectedTab,
                    searchText: $searchText,
                    isImporting: $isImporting,
                    showingPhotosImport: $showingPhotosImport,
                    isScrolled: scrollOffset > 50
                )
                .zIndex(10)

                // Download progress bar
                if !downloadManager.downloads.isEmpty {
                    DownloadProgressBar(downloads: downloadManager.downloads)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                switch selectedTab {
                case .discover:
                    DiscoverView()
                default:
                    if wallpaperManager.wallpapers.isEmpty && selectedTab != .discover {
                        Color.clear
                            .overlay { EmptyLibraryView(isImporting: $isImporting) }
                    } else {
                        switch selectedTab {
                        case .home:
                            HomeView()
                        case .explore:
                            ExploreView(searchText: searchText)
                        case .popular:
                            PopularView()
                        default:
                            HomeView()
                        }
                    }
                }
            }
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
        .alert("Import Error", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .alert(item: $errorReporter.current) { err in
            Alert(
                title: Text(err.title),
                message: Text(err.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView(isPresented: $showingOnboarding)
        }
        .sheet(isPresented: $showingPhotosImport) {
            CreateFromPhotosView()
                .environmentObject(wallpaperManager)
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
                            await MainActor.run { importError = error.localizedDescription }
                        }
                    }
                }
            }
        case .failure(let error):
            Log.ui.error("File picker error: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Drop

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task {
                    do { _ = try await wallpaperManager.importVideo(from: url) }
                    catch { await MainActor.run { importError = error.localizedDescription } }
                }
            }
        }
    }
}

// MARK: - Empty Library View

struct EmptyLibraryView: View {
    @Binding var isImporting: Bool
    @State private var pulseScale: CGFloat = 1.0
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                // Outer glow rings
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Color.accentColor.opacity(0.08 - Double(i) * 0.02), lineWidth: 1)
                        .frame(width: 160 + CGFloat(i) * 40, height: 160 + CGFloat(i) * 40)
                        .scaleEffect(pulseScale + CGFloat(i) * 0.02)
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.accentColor.opacity(0.15), .clear],
                            center: .center, startRadius: 20, endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                    .scaleEffect(pulseScale)

                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentColor, .accentColor.opacity(0.6)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .neonGlow(.accentColor, isActive: true, radius: 12)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    pulseScale = 1.05
                }
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
                .background(
                    ZStack {
                        Capsule().fill(Color.accentColor)
                        Capsule().fill(Color.white.opacity(isHovering ? 0.15 : 0))
                    }
                )
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .scaleEffect(isHovering ? 1.05 : 1.0)
            .neonGlow(.accentColor, isActive: isHovering, radius: 16)
            .animation(.spring(response: Anim.enter, dampingFraction: 0.7), value: isHovering)
            .onHover { h in isHovering = h }

            Text("Drag and drop MP4, MOV, or M4V files")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.3))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Download Progress Bar

struct DownloadProgressBar: View {
    let downloads: [DownloadManager.Download]

    private var activeDownloads: [DownloadManager.Download] {
        downloads.filter { $0.status == .downloading || $0.status == .waiting }
    }

    private var totalProgress: Double {
        let active = activeDownloads
        guard !active.isEmpty else { return 1.0 }
        return active.reduce(0) { $0 + $1.progress } / Double(active.count)
    }

    var body: some View {
        if !activeDownloads.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)

                if let current = activeDownloads.first {
                    Text(current.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                }

                Spacer()

                // Progress percentage
                Text("\(Int(totalProgress * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor)

                if activeDownloads.count > 1 {
                    Text("\(activeDownloads.count) files")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.03))
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: geo.size.width * totalProgress)
                            .animation(.easeInOut(duration: 0.3), value: totalProgress)
                    }
                }
            )
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WallpaperManager.shared)
}
