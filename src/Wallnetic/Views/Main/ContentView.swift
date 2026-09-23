import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var errorReporter = ErrorReporter.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @StateObject private var dynamicAccent = DynamicAccent.shared
    @State private var selectedTab: NavigationTab = .home
    @State private var isImporting = false
    @State private var showingPhotosImport = false
    @State private var searchText = ""
    @State private var scrollOffset: CGFloat = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasSeenDesktopHint") private var hasSeenDesktopHint = false
    @State private var showingOnboarding = false
    @State private var importError: String?
    @State private var isDropTargeted = false
    @State private var pendingImports = 0
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
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

                // #228: one-time reassurance that the wallpaper is independent
                // of this window (the desktop render keeps playing when the
                // window is closed). Shown once the user actually has wallpapers,
                // which is when the misconception arises.
                if hasCompletedOnboarding && !hasSeenDesktopHint && !wallpaperManager.wallpapers.isEmpty {
                    DesktopKeepsPlayingHint(
                        openSettings: { openWindow(id: "settings") },
                        dismiss: {
                            withAnimation(.easeOut(duration: Anim.medium)) { hasSeenDesktopHint = true }
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                switch selectedTab {
                case .discover:
                    DiscoverView()
                default:
                    if wallpaperManager.wallpapers.isEmpty && selectedTab != .discover {
                        Color.clear
                            .overlay {
                                EmptyLibraryView(isImporting: $isImporting) {
                                    selectedTab = .discover
                                }
                            }
                    } else {
                        switch selectedTab {
                        case .home:
                            HomeView()
                        case .explore:
                            ExploreView(searchText: $searchText)
                        case .popular:
                            PopularView()
                        default:
                            HomeView()
                        }
                    }
                }
            }
        }
        .ambientStage()
        .preferredColorScheme(themeManager.appearanceMode.swiftUIColorScheme)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.movie] + WallpaperManager.supportedImportExtensions.compactMap { UTType(filenameExtension: $0) },
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: Radius.panel)
                    .fill(Surface.windowFill.opacity(0.95))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.panel)
                            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8]))
                    }
                    .overlay {
                        Label("Drop videos to add to your library", systemImage: "square.and.arrow.down")
                            .font(Typo.title2)
                    }
                    .padding(Space.md)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            if pendingImports > 0 {
                HStack(spacing: Space.sm) {
                    ProgressView().controlSize(.small)
                    Text("Importing \(pendingImports) file(s)…")
                        .font(Typo.body)
                }
                .padding(Space.md)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.control))
                .padding(Space.lg)
            }
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
        .environment(\.accentTheme, dynamicAccent.theme)
        .onAppear {
            if !hasCompletedOnboarding {
                showingOnboarding = true
                hasCompletedOnboarding = true
            }
            dynamicAccent.applyFrom(wallpaper: wallpaperManager.currentWallpaper)
        }
        .onChange(of: wallpaperManager.currentWallpaper) { newWp in
            dynamicAccent.applyFrom(wallpaper: newWp)
        }
    }

    // MARK: - Import

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task { await importFiles(urls) }
        case .failure(let error):
            Log.ui.error("File picker error: \(error.localizedDescription, privacy: .public)")
            importError = error.localizedDescription
        }
    }

    @MainActor
    private func importFiles(_ urls: [URL]) async {
        pendingImports += urls.count
        for url in urls {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
                pendingImports -= 1
            }
            do {
                _ = try await wallpaperManager.importVideo(from: url)
            } catch {
                let message = "\(url.lastPathComponent): \(error.localizedDescription)"
                importError = [importError, message].compactMap { $0 }.joined(separator: "\n")
            }
        }
    }

    // MARK: - Drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        for provider in fileProviders {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                Task { @MainActor in
                    let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                    guard let url else {
                        importError = error?.localizedDescription ?? "The dropped file could not be read. Try importing it with the file picker."
                        return
                    }
                    await importFiles([url])
                }
            }
        }
        return !fileProviders.isEmpty
    }
}

// MARK: - Empty Library View

struct EmptyLibraryView: View {
    @Binding var isImporting: Bool
    var onDiscover: () -> Void = {}

    var body: some View {
        VStack(spacing: Space.xl) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.accentColor)
                .frame(width: 104, height: 104)
                .background(Surface.glassControl, in: RoundedRectangle(cornerRadius: Radius.panel))
                .accessibilityHidden(true)

            VStack(spacing: Space.sm) {
                Text("Make your desktop your own")
                    .font(Typo.display)
                    .tracking(Typo.displayTracking)
                    .foregroundStyle(.primary)

                Text("Start with a video you love. Add it to your library, then set it as your live wallpaper.")
                    .font(Typo.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 360)
            }
            .multilineTextAlignment(.center)

            HStack(spacing: Space.sm) {
                Button {
                    isImporting = true
                } label: {
                    Label("Import videos", systemImage: "plus")
                        .font(Typo.button)
                        .padding(.horizontal, Space.xs)
                        .padding(.vertical, Space.xxs)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Browse sources", action: onDiscover)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }

            VStack(spacing: Space.xxs) {
                Text("You can also drag files into this window")
                    .font(Typo.caption)
                Text("MP4 · MOV · M4V · HEVC · GIF · WebM · WebP")
                    .font(Typo.data)
            }
            .foregroundStyle(.secondary)
        }
        .padding(Space.xxl)
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
                        .foregroundColor(.primary.opacity(0.8))
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
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Surface.glassControl)
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

// MARK: - Desktop-Keeps-Playing Hint (#228)

/// One-time inline banner clarifying that closing the window doesn't stop the
/// wallpaper — the desktop render is owned by DesktopWindowController, not this
/// SwiftUI window. Matches the DownloadProgressBar inline-strip pattern.
struct DesktopKeepsPlayingHint: View {
    let openSettings: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "sparkles.tv.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.accentColor)
                .neonGlow(.accentColor, isActive: true, radius: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text("Your wallpaper plays on the desktop — closing this window won't stop it.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary.opacity(0.9))
                Text("Want it fully out of the way? Turn on Hide Dock icon in Settings → General to run from the menu bar.")
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.5))
            }

            Spacer(minLength: Space.sm)

            Button("Open Settings", action: openSettings)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.accentColor)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.primary.opacity(0.55))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .suppressFocusRing()
            .help("Dismiss")
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.xs + 2)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Surface.glassControl)
                Rectangle().fill(LinearGradient(
                    colors: [Color.accentColor.opacity(0.10), .clear],
                    startPoint: .leading, endPoint: .trailing))
            }
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(Surface.hairline).frame(height: 0.5)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WallpaperManager.shared)
}
