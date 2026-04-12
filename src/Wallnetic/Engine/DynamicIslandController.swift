import Cocoa
import SwiftUI
import Combine
import UniformTypeIdentifiers

/// Dynamic Island — wraps around the notch on MacBooks, or floats at top-center on other Macs
class DynamicIslandController: ObservableObject {
    static let shared = DynamicIslandController()

    @AppStorage("island.enabled") var isEnabled: Bool = false

    enum IslandState: Equatable {
        case compact
        case expanded
    }

    @Published var state: IslandState = .compact
    @Published var isVisible = false
    @Published var isRenameActive = false
    @Published var hasNotch = false
    @Published var isDragOver = false
    @Published var isImporting = false

    private var islandWindow: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private var autoCollapseTimer: Timer?

    // MARK: - Dimensions

    // Compact — same width for both notch and non-notch
    private let compactHeight: CGFloat = 32

    // Expanded (both)
    private let expandedWidth: CGFloat = 340
    private let expandedHeight: CGFloat = 130

    private init() {
        if isEnabled { show() }
    }

    // MARK: - Notch Detection

    private func detectNotch(for screen: NSScreen) -> CGFloat {
        if #available(macOS 12.0, *) {
            return screen.safeAreaInsets.top
        }
        return 0
    }

    /// Approximate notch width based on known MacBook models (~200pt)
    private func notchWidth(for screen: NSScreen) -> CGFloat {
        let notchH = detectNotch(for: screen)
        guard notchH > 0 else { return 0 }
        // MacBook Pro notch is roughly 200pt wide
        return 200
    }

    /// Compact width: notch space (200pt) + tight side padding
    private let compactWidth: CGFloat = 290 // 45 + 200 + 45

    // MARK: - Show/Hide

    func show() {
        guard islandWindow == nil else { return }

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        hasNotch = detectNotch(for: screen) > 0

        let content = DynamicIslandView()
            .environmentObject(WallpaperManager.shared)
            .environmentObject(self)

        let hostingView = NSHostingView(rootView: content)

        let w = compactWidth
        let h = compactHeight
        let frame = islandFrame(for: screen, width: w, height: h)

        let window = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenNone]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = false
        window.contentView = hostingView
        window.ignoresMouseEvents = false

        window.orderFront(nil)
        islandWindow = window
        isEnabled = true
        isVisible = true

        observeWallpaperChanges()
    }

    func hide() {
        autoCollapseTimer?.invalidate()
        cancellables.removeAll()
        islandWindow?.close()
        islandWindow = nil
        isEnabled = false
        isVisible = false
        state = .compact
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    // MARK: - State Transitions

    func expand() {
        guard state != .expanded else { return }
        state = .expanded
        updateWindowFrame(animated: true)
        scheduleAutoCollapse()
    }

    func collapse() {
        guard state != .compact, !isRenameActive else { return }
        autoCollapseTimer?.invalidate()
        state = .compact
        updateWindowFrame(animated: true)
    }

    func toggleState() {
        if state == .compact { expand() } else { collapse() }
    }

    func scheduleCollapse() {
        scheduleAutoCollapse()
    }

    private func scheduleAutoCollapse() {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.collapse() }
        }
    }

    // MARK: - Window Frame

    private func islandFrame(for screen: NSScreen, width: CGFloat, height: CGFloat) -> NSRect {
        let screenFrame = screen.frame
        let x = screenFrame.midX - width / 2
        // Always at absolute top — on notch Macs the notch blends into the black background
        let y = screenFrame.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func updateWindowFrame(animated: Bool) {
        guard let window = islandWindow, let screen = NSScreen.main else { return }

        let targetWidth = state == .expanded ? expandedWidth : compactWidth
        let targetHeight = state == .expanded ? expandedHeight : compactHeight

        let newFrame = islandFrame(for: screen, width: targetWidth, height: targetHeight)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(newFrame, display: true)
            }
        } else {
            window.setFrame(newFrame, display: true)
        }
    }

    // MARK: - Observers

    private func observeWallpaperChanges() {
        NotificationCenter.default.publisher(for: .wallpaperDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isVisible else { return }
                self.expand()
            }
            .store(in: &cancellables)
    }
}

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
            // Drop zone indicator
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
            // Importing indicator
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

    // MARK: - Compact View — thumbnail | space | play button

    private var compactView: some View {
        HStack(spacing: 0) {
            // LEFT: thumbnail
            thumbnailView(size: 22, radius: 5)
                .padding(.leading, 10)

            // CENTER: notch space
            Spacer()

            // RIGHT: play/pause
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
                    setRandomWallpaper()
                }

                controlButton(icon: "backward.fill", size: 15) {
                    cycleToPreviousWallpaper()
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

    // MARK: - Shared Components

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

    // MARK: - Open Main Window

    private func openMainWindow() {
        openWindow(id: "main")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Thumbnail Loading

    private func loadThumbnail(size: CGFloat) {
        thumbnail = nil
        Task {
            thumbnail = await wallpaperManager.currentWallpaper?.generateThumbnail(
                size: CGSize(width: size, height: size)
            )
        }
    }

    // MARK: - Actions

    private func cycleToPreviousWallpaper() {
        let wallpapers = wallpaperManager.wallpapers
        guard !wallpapers.isEmpty else { return }
        if let current = wallpaperManager.currentWallpaper,
           let idx = wallpapers.firstIndex(where: { $0.id == current.id }) {
            let prevIdx = (idx - 1 + wallpapers.count) % wallpapers.count
            wallpaperManager.setWallpaper(wallpapers[prevIdx])
        } else if let last = wallpapers.last {
            wallpaperManager.setWallpaper(last)
        }
    }

    private func setRandomWallpaper() {
        let candidates = wallpaperManager.wallpapers.filter { $0.id != wallpaperManager.currentWallpaper?.id }
        guard let random = candidates.randomElement() else { return }
        wallpaperManager.setWallpaper(random)
    }

    // MARK: - Drag & Drop Import

    private func handleDrop(providers: [NSItemProvider]) {
        island.isImporting = true

        for provider in providers {
            // Try to load as file URL first
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    guard let url = url else {
                        DispatchQueue.main.async { island.isImporting = false }
                        return
                    }
                    self.importDroppedFile(url: url)
                }
            } else {
                // Fallback: load as file representation
                for type in supportedTypes {
                    if provider.hasItemConformingToTypeIdentifier(type.identifier) {
                        provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { tempURL, error in
                            guard let tempURL = tempURL else {
                                DispatchQueue.main.async { island.isImporting = false }
                                return
                            }
                            // Copy to temp location (file will be deleted after this block)
                            let copyURL = FileManager.default.temporaryDirectory.appendingPathComponent(tempURL.lastPathComponent)
                            try? FileManager.default.removeItem(at: copyURL)
                            try? FileManager.default.copyItem(at: tempURL, to: copyURL)
                            self.importDroppedFile(url: copyURL)
                        }
                        break
                    }
                }
            }
        }
    }

    private func importDroppedFile(url: URL) {
        let ext = url.pathExtension.lowercased()
        let supported = WallpaperManager.supportedImportExtensions
        guard supported.contains(ext) else {
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
                await MainActor.run { island.isImporting = false }
                print("[DynamicIsland] Drop import failed: \(error)")
            }
        }
    }
}

