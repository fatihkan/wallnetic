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
            print("[VideoRenderer] ERROR: File does not exist")
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
                print("[VideoRenderer] Asset is not playable")
                return
            }

            await MainActor.run { [weak self] in
                self?.setupPlayer(with: asset)
            }
        } catch {
            print("[VideoRenderer] Failed to load asset: \(error)")
        }
    }

    private func setupPlayer(with asset: AVURLAsset) {
        // Create player item with performance settings
        let playerItem = AVPlayerItem(asset: asset)

        // Let the system buffer as much as needed for seamless looping
        playerItem.preferredForwardBufferDuration = 0  // No limit — system decides

        // Prefer hardware decoding
        if useHardwareDecoding {
            playerItem.preferredPeakBitRate = 0  // No limit, let hardware handle it
        }

        // Disable audio tracks to save CPU (wallpapers don't need audio)
        disableAudioTracks(for: playerItem)

        // Use AVQueuePlayer with AVPlayerLooper for seamless looping
        queuePlayer = AVQueuePlayer()
        queuePlayer?.automaticallyWaitsToMinimizeStalling = true  // Wait for buffer to avoid black frames
        queuePlayer?.preventsDisplaySleepDuringVideoPlayback = false  // Allow display sleep

        // Trim 0.05s from end to avoid black frame at loop boundary
        let duration = playerItem.asset.duration
        let trimEnd = CMTimeMakeWithSeconds(0.05, preferredTimescale: duration.timescale)
        let loopRange = CMTimeRange(start: .zero, duration: CMTimeSubtract(duration, trimEnd))

        if duration.seconds > 0.1 && loopRange.duration.seconds > 0.1 {
            playerLooper = AVPlayerLooper(player: queuePlayer!, templateItem: playerItem, timeRange: loopRange)
        } else {
            playerLooper = AVPlayerLooper(player: queuePlayer!, templateItem: playerItem)
        }
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
            #if DEBUG
            print("[VideoRenderer] Auto-playing after video ready")
            #endif
        }
    }

    /// Disables all audio tracks to reduce CPU usage
    private func disableAudioTracks(for playerItem: AVPlayerItem) {
        let audioTracks = playerItem.asset.tracks(withMediaType: .audio)
        for track in audioTracks {
            // Find the asset track in the player item
            if let assetTrack = playerItem.tracks.first(where: {
                $0.assetTrack?.trackID == track.trackID
            }) {
                assetTrack.isEnabled = false
            }
        }
    }

    #if DEBUG
    private func setupObservers(for playerItem: AVPlayerItem) {
        playerItemObserver = playerItem.observe(\.status) { item, _ in
            switch item.status {
            case .readyToPlay:
                print("[VideoRenderer] Ready to play")
            case .failed:
                print("[VideoRenderer] Failed: \(item.error?.localizedDescription ?? "unknown")")
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
            #if DEBUG
            print("[VideoRenderer] Play requested, will auto-play when ready")
            #endif
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
