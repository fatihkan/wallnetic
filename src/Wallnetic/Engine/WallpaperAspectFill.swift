import Foundation
import CoreGraphics

/// Aspect-fill crop: keep the video's aspect ratio, cover the whole view,
/// crop overflow. Never stretch.
enum WallpaperAspectFill {

    /// Texture-space crop (origin top-left, 0...1) to sample so `videoSize`
    /// covers `viewSize` without stretching.
    static func textureRect(videoSize: CGSize, viewSize: CGSize) -> CGRect {
        guard videoSize.width > 0, videoSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let videoAspect = videoSize.width / videoSize.height
        let viewAspect = viewSize.width / viewSize.height
        if videoAspect > viewAspect {
            let visible = viewAspect / videoAspect
            return CGRect(x: (1 - visible) / 2, y: 0, width: visible, height: 1)
        }
        let visible = videoAspect / viewAspect
        return CGRect(x: 0, y: (1 - visible) / 2, width: 1, height: visible)
    }

    /// A small backward jump is a stall rolling back to the previous
    /// keyframe (a few frames). A large jump is a genuine loop to t=0.
    /// Hold the last frame for the former; accept the latter.
    static func shouldDiscardRewoundFrame(
        previousSeconds: Double,
        newSeconds: Double
    ) -> Bool {
        guard previousSeconds.isFinite, newSeconds.isFinite,
              previousSeconds >= 0, newSeconds >= 0 else { return false }
        let delta = previousSeconds - newSeconds
        return delta > 0.02 && delta < 1.5
    }
}

/// The aspect-fill crop a Metal quad is built for. The crop belongs to the
/// frame being drawn, not to the latest load: after a switch, the previous
/// video's last frame stays on screen until the next video's first frame
/// arrives, and it keeps its own video's crop meanwhile (#307).
struct WallpaperFrameCrop: Equatable {
    /// Display size of the video the drawn frame came from.
    let videoSize: CGSize
    let viewSize: CGSize

    var textureRect: CGRect {
        WallpaperAspectFill.textureRect(videoSize: videoSize, viewSize: viewSize)
    }

    /// The crop to build before drawing a frame of a `videoSize` video, or
    /// nil when the quad built for `current` already matches.
    static func rebuild(_ current: WallpaperFrameCrop?, forFrameOf videoSize: CGSize,
                        viewSize: CGSize) -> WallpaperFrameCrop? {
        let crop = WallpaperFrameCrop(videoSize: videoSize, viewSize: viewSize)
        return crop == current ? nil : crop
    }
}
