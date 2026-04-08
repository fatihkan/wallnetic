import Cocoa
import SwiftUI
import Combine

/// Dynamic Island — floating pill UI stuck to the very top edge of the screen
class DynamicIslandController: ObservableObject {
    static let shared = DynamicIslandController()

    // MARK: - Settings

    @AppStorage("island.enabled") var isEnabled: Bool = false

    // MARK: - State

    enum IslandState: Equatable {
        case compact
        case expanded
    }

    @Published var state: IslandState = .compact
    @Published var isVisible = false

    private var islandWindow: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private var autoCollapseTimer: Timer?

    // MARK: - Dimensions

    private let compactWidth: CGFloat = 260
    private let compactHeight: CGFloat = 32
    private let expandedWidth: CGFloat = 340
    private let expandedHeight: CGFloat = 130

    private init() {
        if isEnabled { show() }
    }

    // MARK: - Show/Hide

    func show() {
        guard islandWindow == nil else { return }

        let content = DynamicIslandView()
            .environmentObject(WallpaperManager.shared)
            .environmentObject(self)

        let hostingView = NSHostingView(rootView: content)

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.frame
        // Stick to the absolute top of the screen, centered
        let x = screenFrame.midX - compactWidth / 2
        let y = screenFrame.maxY - compactHeight

        let window = NSPanel(
            contentRect: NSRect(x: x, y: y, width: compactWidth, height: compactHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        // Above everything — even the menu bar
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

    @Published var isRenameActive = false

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

    /// Called after rename closes to resume auto-collapse
    func scheduleCollapse() {
        scheduleAutoCollapse()
    }

    private func scheduleAutoCollapse() {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.collapse()
            }
        }
    }

    // MARK: - Window Frame

    private func updateWindowFrame(animated: Bool) {
        guard let window = islandWindow, let screen = NSScreen.main else { return }

        let screenFrame = screen.frame
        let targetWidth = state == .expanded ? expandedWidth : compactWidth
        let targetHeight = state == .expanded ? expandedHeight : compactHeight
        // Always centered, always touching the top edge
        let x = screenFrame.midX - targetWidth / 2
        let y = screenFrame.maxY - targetHeight

        let newFrame = NSRect(x: x, y: y, width: targetWidth, height: targetHeight)

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

    // MARK: - Wallpaper Change Observer

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
        // Top-left corner — flat (no radius)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Top-right corner — flat
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Bottom-right corner — rounded
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRadius))
        path.addArc(center: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY - bottomRadius),
                     radius: bottomRadius, startAngle: .zero, endAngle: .degrees(90), clockwise: false)
        // Bottom-left corner — rounded
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

    @State private var isHovering = false
    @State private var thumbnail: NSImage?
    @State private var isRenaming = false
    @State private var renameText = ""

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
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
            if hovering { island.expand() }
        }
        .onTapGesture { island.toggleState() }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: island.state)
    }

    // MARK: - Compact View

    private var compactView: some View {
        HStack(spacing: 8) {
            // Thumbnail
            if let thumb = thumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 22, height: 22)
            }

            Text(wallpaperManager.currentWallpaper?.displayName ?? "No Wallpaper")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)

            Spacer(minLength: 2)

            // Playback indicator
            Image(systemName: wallpaperManager.isPlaying ? "play.fill" : "pause.fill")
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .frame(width: 260, height: 32)
        .onChange(of: wallpaperManager.currentWallpaper?.id) { _ in
            thumbnail = nil
            Task {
                thumbnail = await wallpaperManager.currentWallpaper?.generateThumbnail(
                    size: CGSize(width: 44, height: 44)
                )
            }
        }
        .task {
            thumbnail = await wallpaperManager.currentWallpaper?.generateThumbnail(
                size: CGSize(width: 44, height: 44)
            )
        }
    }

    // MARK: - Expanded View

    private var expandedView: some View {
        VStack(spacing: 0) {
            // Top section: thumbnail + info
            HStack(spacing: 12) {
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.08))
                        .frame(width: 56, height: 56)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundColor(.white.opacity(0.2))
                        }
                }

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

                // Rename button
                controlButton(icon: "pencil", size: 12) {
                    if let wp = wallpaperManager.currentWallpaper {
                        renameText = wp.displayName
                        isRenaming = true
                        island.isRenameActive = true
                    }
                }

                // Waveform-style indicator
                HStack(spacing: 2) {
                    ForEach(0..<4, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(.white.opacity(wallpaperManager.isPlaying ? 0.5 : 0.15))
                            .frame(width: 2.5, height: barHeight(for: i))
                    }
                }
                .frame(width: 16, height: 18)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Playback controls — tight below info
            HStack(spacing: 24) {
                controlButton(icon: "shuffle", size: 13) {
                    setRandomWallpaper()
                }

                controlButton(icon: "backward.fill", size: 15) {
                    cycleToPreviousWallpaper()
                }

                // Play/Pause — larger
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
        .onChange(of: wallpaperManager.currentWallpaper?.id) { _ in
            thumbnail = nil
            Task {
                thumbnail = await wallpaperManager.currentWallpaper?.generateThumbnail(
                    size: CGSize(width: 112, height: 112)
                )
            }
        }
        .task {
            thumbnail = await wallpaperManager.currentWallpaper?.generateThumbnail(
                size: CGSize(width: 112, height: 112)
            )
        }
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

    // MARK: - Helpers

    private func controlButton(icon: String, size: CGFloat, color: Color = .white.opacity(0.5), action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundColor(color)
        }
        .buttonStyle(.plain)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let heights: [CGFloat] = [8, 14, 10, 16]
        return wallpaperManager.isPlaying ? heights[index] : 4
    }

    private func cycleToPreviousWallpaper() {
        let wallpapers = wallpaperManager.wallpapers
        guard !wallpapers.isEmpty else { return }
        if let current = wallpaperManager.currentWallpaper,
           let idx = wallpapers.firstIndex(where: { $0.id == current.id }) {
            let prevIdx = (idx - 1 + wallpapers.count) % wallpapers.count
            wallpaperManager.setWallpaper(wallpapers[prevIdx])
        } else {
            wallpaperManager.setWallpaper(wallpapers.last!)
        }
    }

    private func setRandomWallpaper() {
        let wallpapers = wallpaperManager.wallpapers
        guard wallpapers.count > 1 else { return }
        var random = wallpapers.randomElement()!
        while random.id == wallpaperManager.currentWallpaper?.id {
            random = wallpapers.randomElement()!
        }
        wallpaperManager.setWallpaper(random)
    }
}
