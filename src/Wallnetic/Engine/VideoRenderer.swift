import Cocoa
import AVFoundation
import AVKit

/// Handles video playback and rendering for live wallpapers
/// Optimized for minimal CPU usage
class VideoRenderer: NSObject {
    private var player: AVPlayer?
    private var playerLooper: AVPlayerLooper?
    private var queuePlayer: AVQueuePlayer?
    private var playerItemObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?

    let view: AVPlayerView

    // Performance settings
    private let preferredBufferDuration: TimeInterval = 2.0  // Seconds of video to buffer
    private let useHardwareDecoding = true

    // Flag to auto-play when video is ready
    private var shouldPlayWhenReady = false

    override init() {
        view = AVPlayerView()
        super.init()

        // Configure AVPlayerView for performance
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor

        // Disable unnecessary features for performance
        view.allowsPictureInPicturePlayback = false
        view.showsFullScreenToggleButton = false

        // Enable layer-backed rendering for better performance
        view.layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    deinit {
        cleanup()
    }

    // MARK: - Video Loading

    /// Loads a video file for playback with performance optimizations
    func loadVideo(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            Log.video.error("File does not exist: \(url.path, privacy: .public)")
            return
        }

        // Clean up existing player
        cleanup()

        // Create asset with optimized loading options
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false,  // Faster loading
        ])

        // Load only video track, skip audio for wallpapers
        Task { [weak self] in
            await self?.loadAssetAsync(asset: asset)
        }
    }

    private func loadAssetAsync(asset: AVURLAsset) async {
        do {
            // Pre-load required properties asynchronously
            let isPlayable = try await asset.load(.isPlayable)
            guard isPlayable else {
                Log.video.error("Asset is not playable")
                return
            }

            await MainActor.run { [weak self] in
                self?.setupPlayer(with: asset)
            }
        } catch {
            Log.video.error("Failed to load asset: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func setupPlayer(with asset: AVURLAsset) {
        // Create player item with performance settings
        let playerItem = AVPlayerItem(asset: asset)

        // Optimize buffering - only buffer what we need
        playerItem.preferredForwardBufferDuration = preferredBufferDuration

        // Prefer hardware decoding
        if useHardwareDecoding {
            playerItem.preferredPeakBitRate = 0  // No limit, let hardware handle it
        }

        // Audio disabled via player.isMuted + volume=0 below

        // Use AVQueuePlayer with AVPlayerLooper for seamless looping
        queuePlayer = AVQueuePlayer()
        queuePlayer?.automaticallyWaitsToMinimizeStalling = false  // Start immediately
        queuePlayer?.preventsDisplaySleepDuringVideoPlayback = false  // Allow display sleep

        playerLooper = AVPlayerLooper(player: queuePlayer!, templateItem: playerItem)
        player = queuePlayer

        // Configure player for optimal performance
        player?.isMuted = true  // No audio needed
        player?.volume = 0  // Ensure no audio processing

        // Set player on view
        view.player = player

        // Observe status for debugging only in debug builds
        #if DEBUG
        setupObservers(for: playerItem)
        #endif

        // Auto-play if requested before video was ready
        if shouldPlayWhenReady {
            player?.play()
            shouldPlayWhenReady = false
            Log.video.debug("Auto-playing after video ready")
        }
    }

    // Audio disabled via player.isMuted + volume=0 (no deprecated tracks API needed)

    #if DEBUG
    private func setupObservers(for playerItem: AVPlayerItem) {
        playerItemObserver = playerItem.observe(\.status) { item, _ in
            switch item.status {
            case .readyToPlay:
                Log.video.debug("Ready to play")
            case .failed:
                Log.video.error("Failed: \(item.error?.localizedDescription ?? "unknown", privacy: .public)")
            default:
                break
            }
        }
    }
    #endif

    // MARK: - Playback Control

    func play() {
        if player != nil {
            player?.play()
        } else {
            // Video not ready yet, play when ready
            shouldPlayWhenReady = true
            Log.video.debug("Play requested, will auto-play when ready")
        }
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
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        playerLooper?.disableLooping()
        playerItemObserver = nil
        rateObserver = nil
        playerLooper = nil
        queuePlayer = nil
        player = nil
        view.player = nil
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

    var duration: CMTime? {
        return player?.currentItem?.duration
    }

    // MARK: - Layout

    func updateLayout() {
        // AVPlayerView handles layout automatically
    }
}
