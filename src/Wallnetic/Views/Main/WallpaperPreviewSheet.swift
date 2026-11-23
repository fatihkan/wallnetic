import SwiftUI
import AppKit

// MARK: - Model

/// State of one wallpaper preview (#349). Nothing here changes the desktop
/// until `apply` runs.
@MainActor
final class WallpaperPreviewModel: ObservableObject {
    /// A display the wallpaper can be previewed for and applied to.
    struct Target: Identifiable, Hashable {
        let id: CGDirectDisplayID
        let name: String
        let size: CGSize
        let visibleFraction: CGRect
        let scale: CGFloat

        static func current() -> [Target] {
            NSScreen.screens.compactMap { screen in
                guard let id = screen.displayID else { return nil }
                return Target(id: id, name: screen.localizedName, size: screen.frame.size,
                              visibleFraction: WallpaperPreviewLayout.visibleFraction(
                                screenFrame: screen.frame, visibleFrame: screen.visibleFrame),
                              scale: screen.backingScaleFactor)
            }
        }
    }

    let wallpaper: Wallpaper
    let targets: [Target]
    /// The Scaling choice needs the Metal renderer.
    let offersScaling: Bool
    @Published var targetID: CGDirectDisplayID
    /// A draft: saved with the wallpaper only when it is applied.
    @Published var scaling: WallpaperScaling {
        didSet { stage?.setScaling(scaling) }
    }
    @Published private(set) var isPlaying = false
    @Published private(set) var stage: WallpaperPreviewStage?
    private let savedScaling: WallpaperScaling
    private var resumeWhenShown = false

    init(wallpaper: Wallpaper, targets: [Target] = Target.current()) {
        self.wallpaper = wallpaper
        self.targets = targets
        offersScaling = WallpaperManager.shared.useMetalRenderer && MetalVideoRenderer.isSupported
        savedScaling = WallpaperScalingStore.shared.scaling(for: wallpaper.url)
        scaling = savedScaling
        let main = NSScreen.main?.displayID
        targetID = targets.first { $0.id == main }?.id ?? targets.first?.id ?? 0
    }

    var target: Target? { targets.first { $0.id == targetID } }

    func start(autoplay: Bool) {
        guard stage == nil else { return }
        let stage = WallpaperPreviewStage(url: wallpaper.url, scaling: scaling,
                                          useMetal: offersScaling, autoplay: autoplay)
        self.stage = stage
        isPlaying = stage.isPlaying
    }

    func togglePlayback() {
        guard let stage else { return }
        if stage.isPlaying { stage.pause() } else { stage.play() }
        isPlaying = stage.isPlaying
    }

    /// The window was hidden or minimized: nothing is watching the preview.
    func suspend() {
        guard let stage, stage.isPlaying else { return }
        resumeWhenShown = true
        stage.pause()
        isPlaying = false
    }

    func resume() {
        guard let stage, resumeWhenShown else { return }
        resumeWhenShown = false
        stage.play()
        isPlaying = stage.isPlaying
    }

    func stop() {
        stage?.stop()
        stage = nil
        isPlaying = false
    }

    /// Saves the scaling draft and sets the wallpaper: on every display, or
    /// only on the previewed one, which leaves the others as they are.
    func apply(toAllDisplays: Bool, manager: WallpaperManager) {
        if scaling != savedScaling {
            WallpaperScalingStore.shared.setScaling(scaling, for: wallpaper.url)
        }
        if toAllDisplays {
            manager.setWallpaper(wallpaper)
        } else if let screen = NSScreen.screens.first(where: { $0.displayID == targetID }) {
            if manager.wallpaperMode != .different { manager.setWallpaperMode(.different) }
            manager.setWallpaper(wallpaper, for: screen)
        }
    }
}

// MARK: - Sheet

/// Try a wallpaper before it reaches the desktop (#349): it plays here with
/// its loop range, scaling, the current effects and the Desktop Clock, at
/// the chosen display's shape. Close leaves the desktop untouched.
struct WallpaperPreviewSheet: View {
    @StateObject private var model: WallpaperPreviewModel
    @EnvironmentObject private var wallpaperManager: WallpaperManager
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The room the stage has in the sheet.
    private static let stageBounds = CGSize(width: 720, height: 420)

    init(wallpaper: Wallpaper) {
        _model = StateObject(wrappedValue: WallpaperPreviewModel(wallpaper: wallpaper))
    }

    private var stageSize: CGSize {
        WallpaperPreviewLayout.stageSize(displaySize: model.target?.size ?? CGSize(width: 16, height: 9),
                                         fitting: Self.stageBounds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.wallpaper.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text("A preview. Your desktop stays as it is until you apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            stage
                .frame(width: stageSize.width, height: stageSize.height)
                .frame(maxWidth: .infinity)

            controls

            Divider()

            HStack(spacing: Space.xs) {
                Button("Close") { close() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if model.targets.count > 1, let target = model.target {
                    Button("Apply to \(target.name)") { apply(toAllDisplays: false) }
                    Button("Apply to All Displays") { apply(toAllDisplays: true) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Apply") { apply(toAllDisplays: true) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(Space.lg)
        .frame(width: Self.stageBounds.width + Space.lg * 2)
        .preferredColorScheme(themeManager.appearanceMode.swiftUIColorScheme)
        .onAppear { model.start(autoplay: !reduceMotion) }
        .onDisappear { model.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didHideNotification)) { _ in
            model.suspend()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didUnhideNotification)) { _ in
            model.resume()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)) { note in
            if (note.object as? NSWindow)?.attachedSheet != nil { model.suspend() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)) { note in
            if (note.object as? NSWindow)?.attachedSheet != nil { model.resume() }
        }
    }

    @ViewBuilder
    private var stage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color.black)
            if let stage = model.stage, let target = model.target {
                PreviewStageHost(stage: stage, visibleFraction: target.visibleFraction, scale: target.scale)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.target.map {
            String(localized: "Preview of \(model.wallpaper.displayName) on \($0.name)")
        } ?? String(localized: "Preview of \(model.wallpaper.displayName)"))
        .accessibilityValue(model.isPlaying ? "Playing" : "Paused")
    }

    private var controls: some View {
        HStack(spacing: Space.md) {
            Button {
                model.togglePlayback()
            } label: {
                Label(model.isPlaying ? "Pause Preview" : "Play Preview",
                      systemImage: model.isPlaying ? "pause.fill" : "play.fill")
            }
            .keyboardShortcut(.space, modifiers: [])

            if model.targets.count > 1 {
                Picker("Display", selection: $model.targetID) {
                    ForEach(model.targets) { target in
                        Text(target.name).tag(target.id)
                    }
                }
                .frame(maxWidth: 240)
            }

            if model.offersScaling {
                Picker("Scaling", selection: $model.scaling) {
                    ForEach(WallpaperScaling.allCases) { scaling in
                        Text(scaling.title).tag(scaling)
                    }
                }
                .frame(maxWidth: 300)
            }

            Spacer(minLength: 0)
        }
    }

    private func apply(toAllDisplays: Bool) {
        model.apply(toAllDisplays: toAllDisplays, manager: wallpaperManager)
        close()
    }

    private func close() {
        model.stop()
        dismiss()
    }
}

// MARK: - Stage host

/// Hosts the stage's AppKit view and tells the stage its size after layout.
private struct PreviewStageHost: NSViewRepresentable {
    let stage: WallpaperPreviewStage
    let visibleFraction: CGRect
    let scale: CGFloat

    func makeNSView(context: Context) -> HostView {
        let host = HostView()
        host.wantsLayer = true
        // The host has no size yet. Its `layout` sizes the stage; shrinking
        // the stage to nothing here would collapse the views inside it.
        stage.view.autoresizingMask = []
        host.addSubview(stage.view)
        return host
    }

    func updateNSView(_ host: HostView, context: Context) {
        host.onLayout = { [weak stage] size in
            stage?.layout(size: size, visibleFraction: visibleFraction, scale: scale)
        }
        host.needsLayout = true
    }

    final class HostView: NSView {
        var onLayout: ((CGSize) -> Void)?

        override func layout() {
            super.layout()
            guard bounds.width > 0, bounds.height > 0 else { return }
            subviews.forEach { $0.frame = bounds }
            onLayout?(bounds.size)
        }

        // The stage only shows; clicks belong to the sheet's controls.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
