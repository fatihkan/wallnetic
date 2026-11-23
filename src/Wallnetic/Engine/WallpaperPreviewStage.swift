import AppKit
import Combine

/// One wallpaper drawn the way a display's wallpaper window draws it, inside
/// a view the preview sheet hosts (#349): the same renderer, loop range,
/// scaling, effects and Desktop Clock. It owns one extra player while it
/// lives and none after `stop()`. It never touches the desktop.
final class WallpaperPreviewStage {
    /// The renderer view with the clock above it, like a wallpaper window's
    /// content.
    let view: NSView
    private(set) var isPlaying = false
    /// Called on the main queue when the first frame shows.
    var onFirstFrame: (() -> Void)?

    private let renderer: WallpaperRenderer
    private let clock: DesktopClockCoordinator
    private let geometry = GeometryBox()
    private var performanceBinding: AnyCancellable?
    private var hasFrame = false
    private var isStopped = false
    /// The clock coordinator keys its views by display; the stage has one.
    private static let clockKey: CGDirectDisplayID = 1

    /// Read by the clock when it draws, so a resized stage needs no rebuild.
    private final class GeometryBox {
        var value: DesktopClockCoordinator.Geometry?
    }

    /// - Parameter autoplay: false shows the first frame and stays paused,
    ///   for Reduce Motion.
    init(url: URL, scaling: WallpaperScaling, useMetal: Bool, autoplay: Bool) {
        let renderer = DesktopWindowController.defaultRenderer(useMetal: useMetal)
        self.renderer = renderer
        let box = geometry
        clock = DesktopClockCoordinator(geometry: { _ in box.value })
        let size = NSSize(width: 640, height: 360)
        view = DesktopWindowController.wallpaperContent(
            rendererView: renderer.rendererView, size: size,
            clockView: clock.makeView(for: Self.clockKey, frame: NSRect(origin: .zero, size: size)))
        let overlay = DesktopWindowController.makeEffectOverlay(in: renderer.rendererView, size: size)
        DesktopWindowController.applyOverlayEffects(to: overlay)
        DesktopWindowController.applyVideoEffects(to: renderer)
        performanceBinding = PerformanceManager.shared.bind(to: renderer)

        renderer.onBecameReady = { [weak self] in
            guard let self, !self.isStopped else { return }
            self.hasFrame = true
            if !autoplay { self.pause() }
            self.refreshClock()
            self.onFirstFrame?()
        }
        renderer.prepareScaling(scaling)
        renderer.loadVideo(url: url, trim: PlaybackTrimStore.shared.trim(for: url))
        // A renderer shows its first frame only while playing; with
        // `autoplay` off it is paused again as soon as that frame arrives.
        renderer.play()
        isPlaying = autoplay
    }

    /// The stage's size and the part of it that stands for the display's
    /// visible area. Call after every layout change.
    func layout(size: CGSize, visibleFraction: CGRect, scale: CGFloat) {
        guard size.width > 0, size.height > 0, !isStopped else { return }
        geometry.value = DesktopClockCoordinator.Geometry(
            frame: CGRect(origin: .zero, size: size),
            visibleFrame: WallpaperPreviewLayout.rect(visibleFraction, in: size),
            scale: scale)
        refreshClock()
        syncMetalScale(fallback: scale)
        redrawIfPaused()
    }

    func setScaling(_ scaling: WallpaperScaling) {
        guard !isStopped else { return }
        renderer.applyScaling(scaling)
    }

    func play() {
        guard !isStopped, !isPlaying else { return }
        isPlaying = true
        renderer.play()
    }

    func pause() {
        guard !isStopped else { return }
        isPlaying = false
        renderer.pause()
    }

    /// Ends the preview's player. The stage cannot be used afterwards.
    func stop() {
        guard !isStopped else { return }
        isStopped = true
        isPlaying = false
        performanceBinding = nil
        renderer.onBecameReady = nil
        clock.cleanup()
        renderer.stop()
    }

    /// A Metal view that joins a window through a sheet can be left with a
    /// layer scale of zero, and then shows nothing although it presents
    /// frames. Give the layer the window's scale.
    private func syncMetalScale(fallback: CGFloat) {
        guard let metal = (renderer as? MetalVideoRenderer)?.metalView,
              let layer = metal.layer as? CAMetalLayer else { return }
        let scale = metal.window?.backingScaleFactor ?? fallback
        if scale > 0, layer.contentsScale != scale { layer.contentsScale = scale }
    }

    private func refreshClock() {
        clock.update([.init(id: Self.clockKey, hasPresentedFrame: hasFrame, reasons: [])])
    }

    /// A paused Metal view keeps its last drawable, stretched, after a
    /// resize. Draw the held frame again at the new size.
    private func redrawIfPaused() {
        guard !isPlaying, hasFrame else { return }
        (renderer as? MetalVideoRenderer)?.metalView.draw()
    }

    deinit { stop() }
}
