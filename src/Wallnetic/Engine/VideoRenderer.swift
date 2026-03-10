import Cocoa
import AVFoundation
import AVKit

/// Handles video playback and rendering for live wallpapers
class VideoRenderer {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var playerLooper: AVPlayerLooper?
    private var queuePlayer: AVQueuePlayer?

    let view: NSView

    init() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        setupPlayerLayer()
    }

    // MARK: - Setup

    private func setupPlayerLayer() {
        playerLayer = AVPlayerLayer()
        playerLayer?.videoGravity = .resizeAspectFill
        playerLayer?.frame = view.bounds
        playerLayer?.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        if let playerLayer = playerLayer {
            view.layer?.addSublayer(playerLayer)
        }
    }

    // MARK: - Video Loading

    /// Loads a video file for playback
    func loadVideo(url: URL) {
        // Clean up existing player
        stop()

        // Create player item
        let asset = AVAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)

        // Use AVQueuePlayer with AVPlayerLooper for seamless looping
        queuePlayer = AVQueuePlayer()
        playerLooper = AVPlayerLooper(player: queuePlayer!, templateItem: playerItem)

        player = queuePlayer
        playerLayer?.player = player

        // Configure for optimal performance
        player?.automaticallyWaitsToMinimizeStalling = true

        // Mute by default (wallpaper shouldn't play audio)
        player?.isMuted = true

        print("Loaded video: \(url.lastPathComponent)")
    }

    // MARK: - Playback Control

    func play() {
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        playerLooper?.disableLooping()
        playerLooper = nil
        queuePlayer = nil
        player = nil
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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer?.frame = view.bounds
        CATransaction.commit()
    }
}

// MARK: - Metal Renderer (Future optimization)
/*
 For better performance, especially with 4K videos, we can implement
 a Metal-based renderer. This would:
 - Use CVPixelBuffer directly from AVPlayer
 - Render using Metal shaders
 - Achieve lower CPU usage

 class MetalVideoRenderer {
     private var device: MTLDevice!
     private var commandQueue: MTLCommandQueue!
     // ... Metal pipeline implementation
 }
 */
