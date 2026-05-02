import SwiftUI
import Photos
import AppKit

/// Wallpaper-from-Photos generator UI (#137).
/// Shown as a sheet from the main window's "+" menu.
struct CreateFromPhotosView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @StateObject private var photos = PhotosLibraryService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var albums: [AlbumDescriptor] = []
    @State private var selectedAlbum: AlbumDescriptor?
    @State private var assets: [PHAsset] = []
    @State private var selectedAssets: Set<String> = []  // PHAsset.localIdentifier

    @State private var perPhotoDuration: Double = 5.0
    @State private var transition: SlideshowGenerator.Transition = .crossfade
    @State private var kenBurns: Bool = true
    @State private var resolution: SlideshowGenerator.Resolution = .hd1080

    @State private var isGenerating = false
    @State private var generationProgress: Double = 0
    @State private var generationError: String?
    @State private var showingSuccess = false
    @State private var generationTask: Task<Void, Never>?

    /// Hard cap on selected photos. With 50 photos × 5s/each + 4K Ken Burns
    /// the output is already ~4 minutes / a few GB — going higher risks
    /// running out of memory and producing a wallpaper too long to loop.
    private static let maxSelection = 50

    private let columns = [GridItem(.adaptive(minimum: 90, maximum: 110), spacing: 6)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            switch photos.authStatus {
            case .notDetermined:
                authPrompt
            case .denied, .restricted:
                deniedState
            case .authorized, .limited:
                authorizedContent
            @unknown default:
                deniedState
            }

            if isGenerating { generatingFooter } else { actionFooter }
        }
        .frame(minWidth: 720, minHeight: 560)
        .onAppear {
            if photos.isAuthorized {
                loadAlbums()
            }
        }
        .onDisappear {
            generationTask?.cancel()
            photos.flushThumbnailCache()
        }
        .alert("Slideshow Error", isPresented: Binding(
            get: { generationError != nil },
            set: { if !$0 { generationError = nil } }
        )) {
            Button("OK") { generationError = nil }
        } message: {
            Text(generationError ?? "")
        }
        .alert("Wallpaper Created", isPresented: $showingSuccess) {
            Button("Done") {
                showingSuccess = false
                dismiss()
            }
        } message: {
            Text("The slideshow has been added to your library.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Create from Photos")
                .font(.title2.bold())
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(isGenerating)
        }
        .padding()
    }

    // MARK: - Auth states

    private var authPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundColor(.accentColor)
            Text("Allow access to Photos to create slideshows from your library.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Allow Photos Access") {
                Task {
                    let status = await photos.requestAuthorization()
                    if status == .authorized || status == .limited {
                        loadAlbums()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var deniedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Photos access is denied.")
                .font(.headline)
            Text("Open System Settings → Privacy & Security → Photos and grant access to Wallnetic.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Authorized content

    @ViewBuilder
    private var authorizedContent: some View {
        VStack(spacing: 0) {
            albumPicker
            Divider()
            assetGrid
        }
    }

    private var albumPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(albums) { album in
                    Button {
                        selectAlbum(album)
                    } label: {
                        Text(album.displayName)
                            .font(.callout)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(selectedAlbum == album ? Color.accentColor.opacity(0.4) : Color.white.opacity(0.06))
                            )
                            .foregroundColor(selectedAlbum == album ? .white : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var assetGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    PhotoThumbnail(asset: asset, isSelected: selectedAssets.contains(asset.localIdentifier))
                        .aspectRatio(1, contentMode: .fit)
                        .onTapGesture { toggleSelection(asset) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Action footers

    private var actionFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("\(selectedAssets.count) of max \(Self.maxSelection) photo\(selectedAssets.count == 1 ? "" : "s") selected")
                            .font(.caption)
                            .foregroundColor(selectedAssets.count >= Self.maxSelection ? .orange : .secondary)
                        if selectedAssets.count >= Self.maxSelection {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Duration").font(.caption2).foregroundColor(.secondary)
                            Picker("", selection: $perPhotoDuration) {
                                Text("3s").tag(3.0)
                                Text("5s").tag(5.0)
                                Text("8s").tag(8.0)
                                Text("10s").tag(10.0)
                            }
                            .frame(width: 70)
                            .labelsHidden()
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Transition").font(.caption2).foregroundColor(.secondary)
                            Picker("", selection: $transition) {
                                Text("None").tag(SlideshowGenerator.Transition.none)
                                Text("Crossfade").tag(SlideshowGenerator.Transition.crossfade)
                            }
                            .frame(width: 110)
                            .labelsHidden()
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Resolution").font(.caption2).foregroundColor(.secondary)
                            Picker("", selection: $resolution) {
                                Text("1080p").tag(SlideshowGenerator.Resolution.hd1080)
                                Text("1440p").tag(SlideshowGenerator.Resolution.qhd1440)
                                Text("4K").tag(SlideshowGenerator.Resolution.uhd4k)
                            }
                            .frame(width: 90)
                            .labelsHidden()
                        }
                        Toggle("Ken Burns", isOn: $kenBurns)
                            .toggleStyle(.checkbox)
                    }
                }

                Spacer()

                Button {
                    startGeneration()
                } label: {
                    Text("Create Wallpaper")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(selectedAssets.count < 2)
            }
            .padding()
        }
    }

    private var generatingFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Generating slideshow…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ProgressView(value: generationProgress)
                }
                Button("Cancel") {
                    generationTask?.cancel()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
        }
    }

    // MARK: - Behavior

    private func loadAlbums() {
        albums = photos.fetchAlbums()
        if let first = albums.first {
            selectAlbum(first)
        }
    }

    private func selectAlbum(_ album: AlbumDescriptor) {
        selectedAlbum = album
        selectedAssets.removeAll()
        assets = photos.fetchAssets(in: album)
    }

    private func toggleSelection(_ asset: PHAsset) {
        if selectedAssets.contains(asset.localIdentifier) {
            selectedAssets.remove(asset.localIdentifier)
        } else if selectedAssets.count < Self.maxSelection {
            selectedAssets.insert(asset.localIdentifier)
        }
        // At cap, additional taps are ignored. The footer label flips to
        // orange to surface the limit.
    }

    private func startGeneration() {
        let chosen = assets.filter { selectedAssets.contains($0.localIdentifier) }
        guard chosen.count >= 2 else { return }

        let settings = SlideshowGenerator.Settings(
            perPhotoDuration: perPhotoDuration,
            transition: transition,
            kenBurns: kenBurns,
            resolution: resolution
        )

        isGenerating = true
        generationProgress = 0

        generationTask = Task {
            defer {
                Task { @MainActor in
                    isGenerating = false
                    generationTask = nil
                }
            }
            do {
                let url = try await SlideshowGenerator().generate(
                    assets: chosen,
                    settings: settings
                ) { progress in
                    Task { @MainActor in self.generationProgress = progress }
                }
                _ = try await wallpaperManager.importVideo(from: url)
                try? FileManager.default.removeItem(at: url)
                await MainActor.run { showingSuccess = true }
            } catch is CancellationError {
                // User cancelled — silent close, no alert.
            } catch SlideshowGenerator.GeneratorError.cancelled {
                // Same — generator surfaced the cancellation as its own type.
            } catch {
                await MainActor.run {
                    generationError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Thumbnail cell

private struct PhotoThumbnail: View {
    let asset: PHAsset
    let isSelected: Bool

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Color.white.opacity(0.06))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white, Color.accentColor)
                    .font(.title3)
                    .padding(4)
            }
        }
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        PhotosLibraryService.shared.requestThumbnail(for: asset, targetSize: CGSize(width: 220, height: 220)) { img in
            image = img
        }
    }
}
