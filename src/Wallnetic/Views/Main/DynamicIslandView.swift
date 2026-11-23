import SwiftUI
import UniformTypeIdentifiers

// MARK: - Dynamic Island View

/// What sits on the island's liquid shape (#352). The shape itself is drawn
/// behind this view by `IslandSurfaceView`.
///
/// - **Compact:** the wallpaper's thumbnail on the left and the playback state
///   on the right. On a display with a notch they sit in the two ears beside
///   it; on any other display the bar also has room for the name.
/// - **Expanded:** the wallpaper's name and its display, and the controls:
///   play or pause, next, Calm Mode, the playback profile and Open Wallnetic.
struct DynamicIslandView: View {
    let metrics: IslandMetrics
    /// The display this island sits on.
    let displayName: String

    @EnvironmentObject var wallpaperManager: WallpaperManager
    @EnvironmentObject var island: DynamicIslandController
    @ObservedObject private var calm = CalmPlaybackSettings.shared
    @ObservedObject private var performance = PerformanceManager.shared

    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var accent: AccentTheme = .signature
    @State private var thumbnail: NSImage?
    @State private var hoveredControl: String?

    private let supportedTypes: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .gif]

    private var isExpanded: Bool { island.state == .expanded }
    private var bar: CGRect { IslandGeometry.compactBar(metrics) }
    private var card: CGRect { IslandGeometry.expandedCard(metrics) }
    private var isCalm: Bool { calm.state.isCalmEnabled }

    /// The content that leaves fades out at once. The content that arrives
    /// waits until the shape has grown, or shrunk, around its place.
    private func contentAnimation(arriving: Bool) -> Animation {
        if reduceMotion { return .easeOut(duration: Anim.fast) }
        return arriving ? .easeOut(duration: 0.18).delay(0.16) : .easeOut(duration: 0.08)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if island.drawsPlainShape { plainShape }

            compactContent
                .frame(width: bar.width, height: bar.height)
                .offset(y: bar.minY)
                .opacity(isExpanded ? 0 : 1)
                .animation(contentAnimation(arriving: !isExpanded), value: island.state)
                .allowsHitTesting(false)

            expandedContent
                .frame(width: card.width, height: card.height - IslandGeometry.hiddenTop(metrics))
                .offset(y: card.minY + IslandGeometry.hiddenTop(metrics))
                .opacity(isExpanded ? 1 : 0)
                .animation(contentAnimation(arriving: isExpanded), value: island.state)
                .allowsHitTesting(isExpanded)
                .accessibilityHidden(!isExpanded)

            stateOverlays
        }
        // No minimum size: the expanded content is larger than the compact
        // window, and a minimum would push the window's views out of place.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Wallnetic Dynamic Island")
    }

    // MARK: - Surface

    /// The shape of the visible state: a flat top at the screen's edge and
    /// rounded lower corners.
    private var outline: some InsettableShape {
        let radius = isExpanded ? IslandGeometry.cardCornerRadius : IslandGeometry.barCornerRadius
        return UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius,
                                      style: .continuous)
    }

    private var shapeFrame: CGRect { isExpanded ? card : bar }

    /// Drawn only when Metal is not usable: a plain dark shape, no liquid.
    private var plainShape: some View {
        outline
            .fill(Color.black.opacity(0.94))
            .frame(width: shapeFrame.width, height: shapeFrame.height)
            .offset(y: shapeFrame.minY)
    }

    @ViewBuilder
    private var stateOverlays: some View {
        if island.isDragOver {
            outline
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
                .frame(width: shapeFrame.width, height: shapeFrame.height)
                .offset(y: shapeFrame.minY)
                .allowsHitTesting(false)
        }
        if island.isImporting {
            outline
                .fill(.black.opacity(0.55))
                .overlay {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.75)
                        .tint(accent.primary)
                }
                .frame(width: shapeFrame.width, height: shapeFrame.height)
                .offset(y: shapeFrame.minY)
                .accessibilityLabel("Importing wallpaper")
        }
    }

    // MARK: - Compact

    private var compactContent: some View {
        HStack(spacing: Space.xs) {
            thumbnailView(size: min(22, bar.height - 8), radius: 6)
            if !metrics.hasNotch {
                Text(wallpaperManager.currentWallpaper?.displayName ?? String(localized: "No wallpaper"))
                    .font(Typo.caption)
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            stateGlyph
        }
        // An ear is `earWidth` wide. Its content sits in the middle of it.
        .padding(.horizontal, metrics.hasNotch ? (IslandGeometry.earWidth - 22) / 2 : 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(stateTitle)
    }

    /// Playing, paused or Calm Mode: a state to read, not a control.
    private var stateGlyph: some View {
        Image(systemName: isCalm ? "leaf.fill" : (wallpaperManager.isPlaying ? "play.fill" : "pause.fill"))
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(isCalm ? accent.primary : .white.opacity(wallpaperManager.isPlaying ? 0.9 : 0.55))
            .frame(width: 22, height: 22)
    }

    private var stateTitle: String {
        if isCalm { return String(localized: "Calm Mode") }
        return wallpaperManager.isPlaying ? String(localized: "Playing") : String(localized: "Paused")
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                thumbnailView(size: 44, radius: Radius.control)

                VStack(alignment: .leading, spacing: 3) {
                    Text(wallpaperManager.currentWallpaper?.displayName ?? String(localized: "No wallpaper"))
                        .font(Typo.button)
                        .tracking(Typo.buttonTracking)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("\(displayName)  ·  \(stateTitle)")
                        .font(Typo.data)
                        .tracking(Typo.dataTracking)
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: Space.xs)

                iconButton("arrow.up.forward.app", label: String(localized: "Open Wallnetic"),
                           size: 14, hit: 30, action: openMainWindow)
            }
            .padding(.horizontal, Space.md)
            .padding(.top, Space.xs)

            Spacer(minLength: 0)

            HStack(spacing: Space.sm) {
                playButton
                iconButton("forward.fill", label: String(localized: "Next wallpaper"), size: 14, hit: 32) {
                    wallpaperManager.cycleToNextWallpaper()
                }
                iconButton("leaf.fill",
                           label: isCalm ? String(localized: "Turn Off Calm Mode") : String(localized: "Turn On Calm Mode"),
                           size: 13, hit: 32, tint: isCalm ? accent.primary : nil) {
                    calm.toggleCalmMode()
                }
                Spacer(minLength: 0)
                profileButton
            }
            .padding(.horizontal, Space.md)
            .padding(.bottom, Space.sm)
        }
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

    /// The one prominent control: a disc in the wallpaper's colour.
    private var playButton: some View {
        let playing = wallpaperManager.isPlaying
        return Button {
            wallpaperManager.togglePlayback()
        } label: {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(accent.on)
                // Nudge the play triangle right so it reads centred.
                .offset(x: playing ? 0 : 1)
                .frame(width: 38, height: 38)
                .background(Circle().fill(accent.primary))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .suppressFocusRing()
        .accessibilityLabel(playing ? "Pause wallpaper" : "Play wallpaper")
    }

    /// Shows the playback profile. A click moves on to the next one.
    private var profileButton: some View {
        let mode = performance.mode
        let hovered = hoveredControl == "profile"
        return Button {
            let all = PerformanceManager.PerformanceMode.allCases
            let index = all.firstIndex(of: mode) ?? 0
            performance.mode = all[(index + 1) % all.count]
        } label: {
            HStack(spacing: 5) {
                Image(systemName: mode.icon)
                    .font(.system(size: 11, weight: .medium))
                Text(mode.title)
                    .font(Typo.caption)
                    .lineLimit(1)
            }
            .foregroundColor(.white.opacity(hovered ? 0.95 : 0.7))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Capsule().fill(.white.opacity(hovered ? 0.14 : 0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .suppressFocusRing()
        .onHover { inside in
            withAnimation(.easeOut(duration: Anim.micro)) { hoveredControl = inside ? "profile" : nil }
        }
        .accessibilityLabel("Playback profile: \(mode.title)")
        .help("Playback profile")
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
        .help(label)
    }

    // MARK: - Actions

    private func openMainWindow() {
        WindowManager.shared.showMainWindow {
            openWindow(id: "main")
        }
    }

    private func loadThumbnail() {
        // Keep the previous frame on screen until the new one arrives —
        // clearing first made every change flash a placeholder.
        Task {
            let next = await wallpaperManager.currentWallpaper?.generateThumbnail(
                size: CGSize(width: 112, height: 112)
            )
            await MainActor.run { thumbnail = next?.image }
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
                    ErrorReporter.shared.report(error, context: String(localized: "Drag & drop import failed"))
                }
            }
        }
    }
}
