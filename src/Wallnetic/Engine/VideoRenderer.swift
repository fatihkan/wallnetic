import Cocoa
import AVFoundation
import QuartzCore

/// Layer-hosted video renderer for live wallpapers.
///
/// Uses `AVPlayerLayer` (not `AVPlayerView`). AVPlayerView composites through
/// an AVKit helper process that frequently draws nothing in desktop-level,
/// non-activating windows — which is exactly a black wallpaper. The in-process
/// layer keeps the last frame on pause, on activation-policy flips, and while
/// the next item is loading.
class VideoRenderer: NSObject {
    let view: NSView

    private var playerLayer: AVPlayerLayer { (view as! PlayerHostView).playerLayer }

    private var player: AVPlayer?
    private var playerLooper: AVPlayerLooper?
    private var queuePlayer: AVQueuePlayer?
    private var itemStatusObserver: NSKeyValueObservation?
    private var currentItemObserver: NSKeyValueObservation?
    private var readyObserver: NSKeyValueObservation?
    private var loadGeneration: UInt64 = 0

    private let preferredBufferDuration: TimeInterval = 4.0
    private var shouldPlayWhenReady = false

    /// True once the layer has actually produced a frame. The overlay window
    /// must stay hidden until this is true, or it covers the desktop in black.
    var hasPresentedFrame = false
    var onBecameReady: (() -> Void)?
    var filterLayer: CALayer? { playerLayer }

    override init() {
        view = PlayerHostView(frame: .zero)
        super.init()
    }

    deinit {
        cleanup()
    }

    // MARK: - Video Loading

    /// Loads a video file. The currently displayed player is kept until the
    /// new item is ready, so a switch cannot flash black.
    func loadVideo(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            Log.video.error("File does not exist: \(url.path, privacy: .public)")
            return
        }

        loadGeneration += 1
        let generation = loadGeneration

        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false
        ])

        Task { [weak self] in
            await self?.loadAssetAsync(asset: asset, generation: generation)
        }
    }

    private func loadAssetAsync(asset: AVURLAsset, generation: UInt64) async {
        do {
            let isPlayable = try await asset.load(.isPlayable)
            guard isPlayable else {
                Log.video.error("Asset is not playable")
                return
            }

            await MainActor.run { [weak self] in
                guard let self, generation == self.loadGeneration else { return }
                self.setupPlayer(with: asset, generation: generation)
            }
        } catch {
            Log.video.error("Failed to load asset: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func setupPlayer(with asset: AVURLAsset, generation: UInt64) {
        guard generation == loadGeneration else { return }

        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = preferredBufferDuration
        playerItem.preferredPeakBitRate = 0

        let newPlayer = AVPlayer(playerItem: playerItem)
        // Keep rate at 1.0. `true` lets AVPlayer slow down when a foreground
        // app steals the decoder — uneven speed — then catch up by seeking
        // to a previous keyframe (a few-frame rewind).
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        newPlayer.preventsDisplaySleepDuringVideoPlayback = false
        newPlayer.isMuted = true
        newPlayer.volume = 0
        newPlayer.actionAtItemEnd = .none

        itemStatusObserver = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self else { return }
            switch item.status {
            case .readyToPlay:
                DispatchQueue.main.async {
                    self.attachIfCurrent(player: newPlayer, item: playerItem, generation: generation)
                }
            case .failed:
                Log.video.error("Failed: \(item.error?.localizedDescription ?? "unknown", privacy: .public)")
            default:
                break
            }
        }
    }

    private var loopObserver: NSObjectProtocol?

    private func attachIfCurrent(player newPlayer: AVPlayer, item: AVPlayerItem, generation: UInt64) {
        guard generation == loadGeneration else { return }
        guard player !== newPlayer else { return }

        let previousPlayer = player
        let previousLooper = playerLooper

        queuePlayer = nil
        playerLooper?.disableLooping()
        playerLooper = nil
        player = newPlayer
        itemStatusObserver = nil

        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self, generation == self.loadGeneration else { return }
            self.player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                if self?.shouldPlayWhenReady == true {
                    self?.player?.play()
                }
            }
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = view.bounds
        playerLayer.player = newPlayer
        CATransaction.commit()
        view.needsLayout = true

        if shouldPlayWhenReady {
            pinOrStart()
        }

        readyObserver = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            guard let self, layer.isReadyForDisplay else { return }
            DispatchQueue.main.async {
                guard generation == self.loadGeneration else { return }
                let firstFrame = !self.hasPresentedFrame
                self.hasPresentedFrame = true
                if firstFrame {
                    self.onBecameReady?()
                }
            }
        }

        previousPlayer?.pause()
        previousLooper?.disableLooping()
        previousPlayer?.replaceCurrentItem(with: nil)

        Log.video.debug("Attached player layer")
    }

    // MARK: - Playback Control

    func play() {
        shouldPlayWhenReady = true
        pinOrStart()
    }

    func pause() {
        shouldPlayWhenReady = false
        player?.pause()
    }

    func stop() {
        cleanup()
    }

    private func cleanup() {
        shouldPlayWhenReady = false
        itemStatusObserver = nil
        currentItemObserver = nil
        readyObserver = nil
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        playerLooper?.disableLooping()
        playerLooper = nil
        queuePlayer = nil
        player = nil
        playerLayer.player = nil
        hasPresentedFrame = false
    }

    func setVolume(_ volume: Float) {
        player?.volume = volume
    }

    func setMuted(_ muted: Bool) {
        player?.isMuted = muted
    }

    func setPlaybackSpeed(_ speed: Float) {
        player?.rate = speed
    }

    // MARK: - Status

    var isPlaying: Bool {
        return player?.rate != 0
    }

    var currentTime: CMTime? {
        return player?.currentTime()
    }

    var currentPlaybackTime: TimeInterval? {
        guard let time = player?.currentTime(), time.isNumeric else { return nil }
        return time.seconds
    }

    var currentPlaybackRate: Float {
        player?.rate ?? 0
    }

    func recoverPlayback() {
        shouldPlayWhenReady = true
        pinOrStart()
    }

    /// Start from a stop, or pin a drifting rate back to 1. Never
    /// `playImmediately` — that seeks to the last keyframe.
    private func pinOrStart() {
        guard let player else { return }
        if WallpaperPlaybackPolicy.shouldIssuePlay(currentRate: player.rate) {
            player.play()
        } else if WallpaperPlaybackPolicy.shouldCorrectRate(
            currentRate: player.rate, intendedToPlay: shouldPlayWhenReady
        ) {
            player.rate = 1
        }
    }

    var duration: CMTime? {
        return player?.currentItem?.duration
    }

    func updateLayout() {}
}

/// Hosts `AVPlayerLayer` as a *sublayer*. Using the player layer as the
/// view's backing layer lets AppKit overwrite `contentsGravity` to `.resize`,
/// which stretches the video. A sublayer with `.resizeAspectFill` keeps
/// aspect and crops to fill.
private final class PlayerHostView: NSView {
    let playerLayer = WallpaperPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.isOpaque = true
        layer?.backgroundColor = NSColor.black.cgColor
        layerContentsRedrawPolicy = .never
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.contentsGravity = .resizeAspectFill
        playerLayer.isOpaque = true
        playerLayer.backgroundColor = NSColor.black.cgColor
        playerLayer.frame = bounds
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        playerLayer.videoGravity = .resizeAspectFill
        CATransaction.commit()
    }
}

/// `action(forKey:)` returning nil disables implicit animations. A default
/// `contents` action on AVPlayerLayer fades every frame and every looper
/// item swap — the twitch this subclass exists to kill.
private final class WallpaperPlayerLayer: AVPlayerLayer {
    override func action(forKey event: String) -> CAAction? {
        nil
    }
}
