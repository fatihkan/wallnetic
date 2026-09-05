import SwiftUI
import UniformTypeIdentifiers

// MARK: - Island Shape

/// Flat top on notch Macs (it continues the notch), softly rounded top when
/// floating on a display without one — a hard edge cut against the menu bar
/// looked like a sticker, not a surface.
struct IslandShape: InsettableShape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var insetAmount: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func inset(by amount: CGFloat) -> IslandShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in outer: CGRect) -> Path {
        let rect = outer.insetBy(dx: insetAmount, dy: insetAmount)
        var path = Path()
        let t = min(topRadius, rect.width / 2, rect.height / 2)
        let b = min(bottomRadius, rect.width / 2, rect.height / 2)
        path.move(to: CGPoint(x: rect.minX + t, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY))
        if t > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - t, y: rect.minY + t),
                        radius: t, startAngle: .degrees(-90), endAngle: .zero, clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - b))
        path.addArc(center: CGPoint(x: rect.maxX - b, y: rect.maxY - b),
                    radius: b, startAngle: .zero, endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + b, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + b, y: rect.maxY - b),
                    radius: b, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + t))
        if t > 0 {
            path.addArc(center: CGPoint(x: rect.minX + t, y: rect.minY + t),
                        radius: t, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Dynamic Island View

/// The island is made of the wallpaper: its glass is tinted by the current
/// wallpaper's derived accent, so it shifts colour when the wallpaper does.
/// Compact stays near-black to merge with the notch; expanded opens into the
/// app's Liquid Glass language.
struct DynamicIslandView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @EnvironmentObject var island: DynamicIslandController

    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var accent: AccentTheme = .signature
    @State private var thumbnail: NSImage?
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var hoveredControl: String?
    @FocusState private var renameFocused: Bool

    private let supportedTypes: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .gif]

    private var isExpanded: Bool { island.state == .expanded }
    private var topRadius: CGFloat { island.hasNotch ? 0 : (isExpanded ? 14 : 10) }
    private var bottomRadius: CGFloat { isExpanded ? 22 : 16 }

    private var stateAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: Anim.fast)
            : .spring(response: 0.36, dampingFraction: 0.82)
    }

    var body: some View {
        Group {
            if isExpanded {
                expandedView
            } else {
                compactView
            }
        }
        .background(islandSurface)
        .clipShape(IslandShape(topRadius: topRadius, bottomRadius: bottomRadius))
        .overlay(stateOverlays)
        .onDrop(of: supportedTypes, isTargeted: $island.isDragOver) { providers in
            handleDrop(providers: providers)
            return true
        }
        .onChange(of: island.isDragOver) { dragging in
            if dragging { island.expand() }
        }
        .onReceive(DynamicAccent.shared.$theme.receive(on: RunLoop.main)) { theme in
            let fade: Animation? = reduceMotion ? nil : .easeInOut(duration: Anim.slow)
            withAnimation(fade) { accent = theme }
        }
        .onChange(of: wallpaperManager.currentWallpaper?.id) { _ in loadThumbnail() }
        .task { loadThumbnail() }
        .animation(stateAnimation, value: island.state)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Wallnetic Dynamic Island")
    }

    // MARK: - Surface

    /// Near-black base so the compact pill continues the notch, with an
    /// accent bloom that only reveals itself in the expanded state.
    private var islandSurface: some View {
        ZStack {
            IslandShape(topRadius: topRadius, bottomRadius: bottomRadius)
                .fill(Color.black.opacity(0.94))

            // Accent bloom, anchored where the thumbnail sits.
            IslandShape(topRadius: topRadius, bottomRadius: bottomRadius)
                .fill(
                    RadialGradient(
                        colors: [
                            accent.primary.opacity((isExpanded ? 0.34 : 0.10) * accent.glow),
                            accent.secondary.opacity((isExpanded ? 0.10 : 0.0) * accent.glow),
                            .clear
                        ],
                        center: UnitPoint(x: 0.16, y: 0.42),
                        startRadius: 6,
                        endRadius: isExpanded ? 260 : 120
                    )
                )
                .blendMode(.plusLighter)

            // Refractive hairline, shared with the app's glass controls.
            IslandShape(topRadius: topRadius, bottomRadius: bottomRadius)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(island.hasNotch ? 0.0 : 0.16), location: 0),
                            .init(color: .white.opacity(0.06), location: 0.5),
                            .init(color: accent.primary.opacity(0.22 * accent.glow), location: 1)
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        }
        .shadow(color: .black.opacity(0.55), radius: isExpanded ? 14 : 8, y: isExpanded ? 6 : 3)
        .shadow(color: accent.primary.opacity(isExpanded ? 0.18 * accent.glow : 0), radius: 24, y: 8)
    }

    @ViewBuilder
    private var stateOverlays: some View {
        if island.isDragOver {
            IslandShape(topRadius: topRadius, bottomRadius: bottomRadius)
                .strokeBorder(accent.primary.opacity(0.9), lineWidth: 1.5)
                .overlay {
                    VStack(spacing: Space.xxs) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(accent.primary)
                        if isExpanded {
                            Text("Drop to import")
                                .font(Typo.caption)
                                .tracking(Typo.captionTracking)
                                .foregroundColor(.white.opacity(0.75))
                        }
                    }
                }
        }
        if island.isImporting {
            IslandShape(topRadius: topRadius, bottomRadius: bottomRadius)
                .fill(.black.opacity(0.55))
                .overlay {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.75)
                        .tint(accent.primary)
                }
                .accessibilityLabel("Importing wallpaper")
        }
    }

    // MARK: - Compact

    private var compactView: some View {
        HStack(spacing: 0) {
            thumbnailView(size: 22, radius: 6)
                .padding(.leading, 10)
            Spacer()
            playButton(size: 12, hit: 28, prominent: false)
                .padding(.trailing, 6)
        }
        .frame(height: island.compactHeight)
    }

    // MARK: - Expanded

    private var expandedView: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                Button { openMainWindow() } label: {
                    thumbnailView(size: 56, radius: Radius.control)
                }
                .buttonStyle(.plain)
                .suppressFocusRing()
                .accessibilityLabel("Open Wallnetic")

                VStack(alignment: .leading, spacing: 3) {
                    if isRenaming {
                        TextField("Name", text: $renameText)
                            .textFieldStyle(.plain)
                            .font(Typo.button)
                            .foregroundColor(.white)
                            .focused($renameFocused)
                            .onSubmit(commitRename)
                            .onExitCommand(perform: cancelRename)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.accent, style: .continuous)
                                    .fill(.white.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Radius.accent, style: .continuous)
                                            .stroke(accent.primary.opacity(0.6), lineWidth: 0.6)
                                    )
                            )
                            .accessibilityLabel("Wallpaper name")
                    } else {
                        Text(wallpaperManager.currentWallpaper?.displayName ?? "No wallpaper")
                            .font(Typo.button)
                            .tracking(Typo.buttonTracking)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if let wp = wallpaperManager.currentWallpaper {
                        Text("\(wp.formattedResolution)  ·  \(wp.formattedDuration)")
                            .font(Typo.data)
                            .tracking(Typo.dataTracking)
                            .foregroundColor(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: Space.xs)

                if isRenaming {
                    iconButton("checkmark", label: "Save name", size: 12, hit: 28, tint: accent.primary, action: commitRename)
                } else {
                    iconButton("pencil", label: "Rename wallpaper", size: 12, hit: 28, action: beginRename)
                        .disabled(wallpaperManager.currentWallpaper == nil)
                }
            }
            .padding(.horizontal, Space.md)
            .padding(.top, Space.sm)

            Spacer(minLength: 0)

            HStack(spacing: Space.lg) {
                iconButton("shuffle", label: "Random wallpaper", size: 13, hit: 32) {
                    wallpaperManager.setRandomWallpaper()
                }
                iconButton("backward.fill", label: "Previous wallpaper", size: 14, hit: 32) {
                    wallpaperManager.cycleToPreviousWallpaper()
                }

                playButton(size: 18, hit: 40, prominent: true)

                iconButton("forward.fill", label: "Next wallpaper", size: 14, hit: 32) {
                    wallpaperManager.cycleToNextWallpaper()
                }

                let fav = wallpaperManager.currentWallpaper?.isFavorite == true
                iconButton(
                    fav ? "heart.fill" : "heart",
                    label: fav ? "Remove from favorites" : "Add to favorites",
                    size: 13, hit: 32,
                    tint: fav ? Color.pink : nil
                ) {
                    if let wp = wallpaperManager.currentWallpaper {
                        wallpaperManager.toggleFavorite(wp)
                    }
                }
            }
            .padding(.bottom, Space.sm)
        }
        .frame(width: 340, height: 132)
    }

    // MARK: - Components

    @ViewBuilder
    private func thumbnailView(size: CGFloat, radius: CGFloat) -> some View {
        ZStack {
            if let thumb = thumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.white.opacity(0.06))
                Image(systemName: "film")
                    .font(.system(size: size * 0.36, weight: .medium))
                    .foregroundColor(.white.opacity(0.22))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }

    /// The one prominent control: an accent-filled disc in the expanded
    /// state, a quiet glyph in the compact one.
    private func playButton(size: CGFloat, hit: CGFloat, prominent: Bool) -> some View {
        let playing = wallpaperManager.isPlaying
        return Button {
            wallpaperManager.togglePlayback()
        } label: {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(prominent ? accent.on : .white.opacity(0.85))
                // Nudge the play triangle right so it reads centred.
                .offset(x: playing || !prominent ? 0 : 1)
                .frame(width: hit, height: hit)
                .background(
                    Circle()
                        .fill(prominent ? accent.primary : .clear)
                        .shadow(color: accent.primary.opacity(prominent ? 0.45 * accent.glow : 0), radius: 10, y: 3)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .suppressFocusRing()
        .accessibilityLabel(playing ? "Pause wallpaper" : "Play wallpaper")
    }

    private func iconButton(
        _ systemName: String,
        label: String,
        size: CGFloat,
        hit: CGFloat,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let hovered = hoveredControl == label
        return Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(tint ?? .white.opacity(hovered ? 0.95 : 0.58))
                .frame(width: hit, height: hit)
                .background(
                    Circle().fill(.white.opacity(hovered ? 0.10 : 0))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .suppressFocusRing()
        .onHover { h in
            withAnimation(.easeOut(duration: Anim.micro)) { hoveredControl = h ? label : nil }
        }
        .accessibilityLabel(label)
    }

    // MARK: - Rename (inline)

    /// A `.sheet` cannot present from a borderless non-activating panel at
    /// menu-bar level, which is what the island is — the old sheet-based
    /// rename silently never appeared. Rename is inline instead.
    private func beginRename() {
        guard let wp = wallpaperManager.currentWallpaper else { return }
        renameText = wp.displayName
        island.isRenameActive = true
        isRenaming = true
        DispatchQueue.main.async { renameFocused = true }
    }

    private func commitRename() {
        defer { endRename() }
        guard let wp = wallpaperManager.currentWallpaper else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != wp.displayName else { return }
        wallpaperManager.renameWallpaper(wp, to: trimmed)
    }

    private func cancelRename() {
        endRename()
    }

    private func endRename() {
        isRenaming = false
        renameFocused = false
        island.isRenameActive = false
        island.scheduleCollapse()
    }

    private func openMainWindow() {
        openWindow(id: "main")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func loadThumbnail() {
        // Keep the previous frame on screen until the new one arrives —
        // clearing first made every change flash a placeholder.
        Task {
            let next = await wallpaperManager.currentWallpaper?.generateThumbnail(
                size: CGSize(width: 112, height: 112)
            )
            await MainActor.run { thumbnail = next }
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
                    island.scheduleCollapse()
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
