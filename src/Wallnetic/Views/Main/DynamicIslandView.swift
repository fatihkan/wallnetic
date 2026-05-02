import SwiftUI
import UniformTypeIdentifiers

// MARK: - Island Shape (flat top, rounded bottom)

struct IslandShape: Shape {
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRadius))
        path.addArc(center: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY - bottomRadius),
                     radius: bottomRadius, startAngle: .zero, endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY - bottomRadius),
                     radius: bottomRadius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.closeSubpath()
        return path
    }
}

// MARK: - Dynamic Island View

struct DynamicIslandView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @EnvironmentObject var island: DynamicIslandController

    @Environment(\.openWindow) private var openWindow
    @State private var isHovering = false
    @State private var thumbnail: NSImage?
    @State private var isRenaming = false
    @State private var renameText = ""

    private let supportedTypes: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .gif]

    private var bottomRadius: CGFloat {
        island.state == .compact ? 16 : 20
    }

    var body: some View {
        Group {
            if island.state == .compact {
                compactView
            } else {
                expandedView
            }
        }
        .background(
            IslandShape(bottomRadius: bottomRadius)
                .fill(.black)
                .shadow(color: .black.opacity(0.6), radius: 8, y: 4)
        )
        .clipShape(IslandShape(bottomRadius: bottomRadius))
        .overlay {
            if island.isDragOver {
                IslandShape(bottomRadius: bottomRadius)
                    .stroke(.white.opacity(0.6), lineWidth: 2)
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white.opacity(0.9))
                            if island.state == .expanded {
                                Text("Drop to import")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
            }
            if island.isImporting {
                IslandShape(bottomRadius: bottomRadius)
                    .fill(.black.opacity(0.5))
                    .overlay {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                            .tint(.white)
                    }
            }
        }
        .onDrop(of: supportedTypes, isTargeted: $island.isDragOver) { providers in
            handleDrop(providers: providers)
            return true
        }
        .onChange(of: island.isDragOver) { dragging in
            if dragging { island.expand() }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
            if hovering { island.expand() }
        }
        .onTapGesture { island.toggleState() }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: island.state)
    }

    // MARK: - Compact View

    private var compactView: some View {
        HStack(spacing: 0) {
            thumbnailView(size: 22, radius: 5)
                .padding(.leading, 10)
            Spacer()
            Button {
                wallpaperManager.togglePlayback()
            } label: {
                Image(systemName: wallpaperManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
        }
        .frame(height: 32)
        .onChange(of: wallpaperManager.currentWallpaper?.id) { _ in loadThumbnail(size: 44) }
        .task { loadThumbnail(size: 44) }
    }

    // MARK: - Expanded View

    private var expandedView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                thumbnailView(size: 56, radius: 10)
                    .onTapGesture { openMainWindow() }

                VStack(alignment: .leading, spacing: 3) {
                    Text(wallpaperManager.currentWallpaper?.displayName ?? "No Wallpaper")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if let wp = wallpaperManager.currentWallpaper {
                        Text("\(wp.formattedResolution) • \(wp.formattedDuration)")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }

                Spacer()

                controlButton(icon: "pencil", size: 12) {
                    if let wp = wallpaperManager.currentWallpaper {
                        renameText = wp.displayName
                        isRenaming = true
                        island.isRenameActive = true
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            HStack(spacing: 24) {
                controlButton(icon: "shuffle", size: 13) {
                    wallpaperManager.setRandomWallpaper()
                }

                controlButton(icon: "backward.fill", size: 15) {
                    wallpaperManager.cycleToPreviousWallpaper()
                }

                Button {
                    wallpaperManager.togglePlayback()
                } label: {
                    Image(systemName: wallpaperManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                controlButton(icon: "forward.fill", size: 15) {
                    wallpaperManager.cycleToNextWallpaper()
                }

                controlButton(
                    icon: wallpaperManager.currentWallpaper?.isFavorite == true ? "heart.fill" : "heart",
                    size: 13,
                    color: wallpaperManager.currentWallpaper?.isFavorite == true ? .pink : .white.opacity(0.5)
                ) {
                    if let wp = wallpaperManager.currentWallpaper {
                        wallpaperManager.toggleFavorite(wp)
                    }
                }
            }
            .padding(.bottom, 14)
        }
        .frame(width: 340, height: 130)
        .onChange(of: wallpaperManager.currentWallpaper?.id) { _ in loadThumbnail(size: 112) }
        .task { loadThumbnail(size: 112) }
        .sheet(isPresented: $isRenaming) {
            if let wp = wallpaperManager.currentWallpaper {
                RenameWallpaperSheet(
                    wallpaper: wp,
                    title: $renameText,
                    onSave: { newTitle in
                        wallpaperManager.renameWallpaper(wp, to: newTitle)
                        isRenaming = false
                        island.isRenameActive = false
                        island.scheduleCollapse()
                    },
                    onCancel: {
                        isRenaming = false
                        island.isRenameActive = false
                        island.scheduleCollapse()
                    }
                )
            }
        }
    }

    // MARK: - Components

    @ViewBuilder
    private func thumbnailView(size: CGFloat, radius: CGFloat) -> some View {
        if let thumb = thumbnail {
            Image(nsImage: thumb)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: radius))
        } else {
            RoundedRectangle(cornerRadius: radius)
                .fill(.white.opacity(0.08))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: size * 0.4))
                        .foregroundColor(.white.opacity(0.2))
                }
        }
    }

    private func controlButton(icon: String, size: CGFloat, color: Color = .white.opacity(0.5), action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundColor(color)
        }
        .buttonStyle(.plain)
    }

    private func openMainWindow() {
        openWindow(id: "main")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func loadThumbnail(size: CGFloat) {
        thumbnail = nil
        Task {
            thumbnail = await wallpaperManager.currentWallpaper?.generateThumbnail(
                size: CGSize(width: size, height: size)
            )
        }
    }

    // MARK: - Drag & Drop

    private func handleDrop(providers: [NSItemProvider]) {
        island.isImporting = true
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url = url else {
                        DispatchQueue.main.async { island.isImporting = false }
                        return
                    }
                    importDroppedFile(url: url)
                }
            } else {
                for type in supportedTypes {
                    if provider.hasItemConformingToTypeIdentifier(type.identifier) {
                        provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { tempURL, _ in
                            guard let tempURL = tempURL else {
                                DispatchQueue.main.async { island.isImporting = false }
                                return
                            }
                            let copyURL = FileManager.default.temporaryDirectory.appendingPathComponent(tempURL.lastPathComponent)
                            try? FileManager.default.removeItem(at: copyURL)
                            try? FileManager.default.copyItem(at: tempURL, to: copyURL)
                            importDroppedFile(url: copyURL)
                        }
                        break
                    }
                }
            }
        }
    }

    private func importDroppedFile(url: URL) {
        let ext = url.pathExtension.lowercased()
        guard WallpaperManager.supportedImportExtensions.contains(ext) else {
            DispatchQueue.main.async { island.isImporting = false }
            return
        }
        Task {
            do {
                let wallpaper = try await wallpaperManager.importVideo(from: url)
                await MainActor.run {
                    wallpaperManager.setWallpaper(wallpaper)
                    island.isImporting = false
                    island.expand()
                }
            } catch {
                await MainActor.run {
                    island.isImporting = false
                    ErrorReporter.shared.report(error, context: "Drag & drop import failed")
                }
            }
        }
    }
}
