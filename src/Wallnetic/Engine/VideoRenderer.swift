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
    private var itemStatusObserver: NSKeyValueObservation?
    private var readyObserver: NSKeyValueObservation?
    private var loadGeneration: UInt64 = 0
    private var loadTask: Task<Void, Never>?

    private let preferredBufferDuration: TimeInterval = 4.0
    private var shouldPlayWhenReady = false
    /// The video and loop range of the latest load, for trim edits.
    private var loadedURL: URL?
    private var loadedTrim: PlaybackTrim?
    private var pendingTrimReload: PendingTrimReload?
    /// The load started by a trim edit, while it is the latest load.
    private var trimReloadGeneration: UInt64?
    /// The load the current player came from.
    private var playerGeneration: UInt64?
    /// The range the current player loops, or nil when it plays the full video.
    private(set) var appliedTrim: PlaybackTrim?
    /// The range the latest load asked for, once it matched the file.
    private var requestedTrim: PlaybackTrim?

    var trimOutcome: (url: URL, applied: Bool)? {
        guard pendingTrimReload == nil, playerGeneration == loadGeneration,
              let loadedURL, requestedTrim != nil else { return nil }
        return (loadedURL, appliedTrim != nil)
    }

    let playbackMonitor = RendererPlaybackMonitor()
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
    func loadVideo(url: URL, trim: PlaybackTrim?) {
        loadTask?.cancel()
        loadGeneration &+= 1
        let generation = loadGeneration
        loadedURL = url
        loadedTrim = trim
        pendingTrimReload = nil
        trimReloadGeneration = nil
        playbackMonitor.beginLoad()
        guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path) else {
            failLoading(.missingFile)
            return
        }

        let trim = TrimmedVideoAsset.usableTrim(trim, for: url)
        requestedTrim = trim
        let asset = TrimmedVideoAsset.sourceAsset(url: url, trim: trim)

        loadTask = Task { @MainActor [weak self] in
            do {
                let isPlayable = try await asset.load(.isPlayable)
                guard !Task.isCancelled, let self, generation == self.loadGeneration else { return }
                guard isPlayable else {
                    self.failLoading(.unplayable)
                    return
                }
                let playback = await TrimmedVideoAsset.playbackAsset(for: asset, trim: trim)
                guard !Task.isCancelled, generation == self.loadGeneration else { return }
                self.setupPlayer(with: playback.asset, trim: playback.trim, generation: generation)
            } catch {
                guard !Task.isCancelled, let self, generation == self.loadGeneration else { return }
                self.failLoading(.loadFailed)
            }
        }
    }

    /// Reloads the current video with an edited loop range, keeping its
    /// play/pause intent. While paused, the reload waits for the next resume,
    /// so a paused display keeps its frame and its Paused status.
    func applyTrim(_ trim: PlaybackTrim?) {
        guard let loadedURL else { return }
        // The full video plays and still would: removing a range that does not
        // apply keeps the current player instead of restarting it.
        if playerGeneration == loadGeneration, appliedTrim == nil,
           TrimmedVideoAsset.usableTrim(trim, for: loadedURL) == nil {
            loadedTrim = trim
            requestedTrim = nil
            pendingTrimReload = nil
            return
        }
        guard shouldPlayWhenReady else {
            pendingTrimReload = trim == loadedTrim ? nil : PendingTrimReload(trim: trim)
            return
        }
        guard trim != loadedTrim else { return }
        loadTrimReload(url: loadedURL, trim: trim)
    }

    /// Loads a trim edit made while paused instead of resuming the old player
    /// outside the edited range. The new player starts once it is ready.
    private func startPendingTrimReload() -> Bool {
        guard let pending = pendingTrimReload, let loadedURL else { return false }
        loadTrimReload(url: loadedURL, trim: pending.trim)
        return true
    }

    private func loadTrimReload(url: URL, trim: PlaybackTrim?) {
        loadVideo(url: url, trim: trim)
        trimReloadGeneration = loadGeneration
    }

    /// While a trim edit loads, the current player still plays the previous
    /// range. Nothing may start it again before the edited player takes over.
    private var isWaitingForTrimReload: Bool {
        trimReloadGeneration == loadGeneration && playerGeneration != loadGeneration
    }

    private func failLoading(_ failure: RendererPlaybackFailure) {
        playbackMonitor.fail(failure)
    }

    private func setupPlayer(with asset: AVAsset, trim: PlaybackTrim?, generation: UInt64) {
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
        newPlayer.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        newPlayer.isMuted = true
        newPlayer.volume = 0
        newPlayer.actionAtItemEnd = .none

        playbackMonitor.attach(newPlayer)
        itemStatusObserver = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self else { return }
            switch item.status {
            case .readyToPlay:
                DispatchQueue.main.async {
                    self.attachIfCurrent(player: newPlayer, item: playerItem, trim: trim, generation: generation)
                }
            case .failed:
                DispatchQueue.main.async {
                    guard generation == self.loadGeneration else { return }
                    self.failLoading(.loadFailed)
                }
            default:
                break
            }
        }
    }

    private var loopObserver: NSObjectProtocol?

    private func attachIfCurrent(player newPlayer: AVPlayer, item: AVPlayerItem, trim: PlaybackTrim?,
                                 generation: UInt64) {
        guard generation == loadGeneration else { return }
        guard player !== newPlayer else { return }

        let previousPlayer = player

        player = newPlayer
        playerGeneration = generation
        appliedTrim = trim
        itemStatusObserver = nil

        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak newPlayer] _ in
            guard let self, let newPlayer, self.player === newPlayer else { return }
            newPlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak newPlayer] finished in
                DispatchQueue.main.async {
                    guard finished, let self, let newPlayer,
                          self.player === newPlayer, self.shouldPlayWhenReady else { return }
                    newPlayer.play()
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
                self.playbackMonitor.framePresented()
                if firstFrame {
                    self.onBecameReady?()
                }
            }
        }

        previousPlayer?.pause()
        previousPlayer?.replaceCurrentItem(with: nil)

        Log.video.debug("Attached player layer")
    }

    // MARK: - Playback Control

    func applyPerformanceMode(_ mode: PerformanceManager.PerformanceMode) {
        // AVPlayerLayer has no direct frame-rate cap for local video. Network
        // bitrate/resolution preferences do not limit local decoding. Changing
        // videoComposition during playback can move the clock backwards, so
        // keep native timing rather than change rate or rebuild the player.
        Log.video.debug("Profile \(mode.rawValue, privacy: .public): AVPlayer keeps source frame timing")
    }

    func play() {
        guard !playbackMonitor.state.isFailed else { return }
        shouldPlayWhenReady = true
        guard !startPendingTrimReload() else { return }
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
        playbackMonitor.reset()
        loadGeneration &+= 1
        loadTask?.cancel()
        loadTask = nil
        shouldPlayWhenReady = false
        loadedURL = nil
        loadedTrim = nil
        requestedTrim = nil
        pendingTrimReload = nil
        trimReloadGeneration = nil
        playerGeneration = nil
        itemStatusObserver = nil
        readyObserver = nil
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        appliedTrim = nil
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
        guard !playbackMonitor.state.isFailed else { return }
        shouldPlayWhenReady = true
        guard !startPendingTrimReload() else { return }
        pinOrStart()
    }

    func maintainPlayback() {
        guard !playbackMonitor.state.isFailed else { return }
        guard shouldPlayWhenReady else { return }
        pinOrStart()
    }

    /// Start from a stop, or pin a drifting rate back to 1. Never
    /// `playImmediately` — that seeks to the last keyframe.
    private func pinOrStart() {
        guard let player, !isWaitingForTrimReload else { return }
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
        guard playerLayer.frame != bounds else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
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
