import AVFoundation

/// What a renderer plays for a video and its stored loop range.
///
/// A trim plays as a passthrough composition holding only the selected range
/// of the original video track: no export, no new file. The item's timeline
/// still starts at zero, so the loop, first-frame, watchdog and Pause After
/// logic is unchanged. When the range cannot be applied (a replaced file, a
/// range outside the loaded track, or a composition that cannot be built),
/// the full video plays instead of a failed or black wallpaper.
enum TrimmedVideoAsset {
    /// The trim to apply to the file at `url`, or nil when the file no longer
    /// matches the trim's fingerprint.
    static func usableTrim(_ trim: PlaybackTrim?, for url: URL) -> PlaybackTrim? {
        guard let trim, trim.matches(VideoFileFingerprint(fileAt: url)) else { return nil }
        return trim
    }

    /// Trimmed sources use precise timing, which the SDK recommends for
    /// compositions and which needs no extra parsing for QuickTime and MPEG-4
    /// files. Untrimmed loads keep approximate timing.
    static func sourceAsset(url: URL, trim: PlaybackTrim?) -> AVURLAsset {
        AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: trim != nil])
    }

    /// The asset to play and the trim in effect, nil when the full video
    /// plays. Composition objects are not Sendable, so this runs inside the
    /// renderer's main-actor load task. The track's properties load
    /// asynchronously first, so the synchronous insert does not block.
    @MainActor
    static func playbackAsset(for source: AVURLAsset, trim: PlaybackTrim?) async -> (asset: AVAsset, trim: PlaybackTrim?) {
        guard let trim else { return (source, nil) }
        do {
            guard let track = try await source.loadTracks(withMediaType: .video).first else { return (source, nil) }
            let (trackRange, transform, _) = try await track.load(.timeRange, .preferredTransform, .formatDescriptions)
            guard let range = trim.timeRange(within: trackRange) else {
                Log.video.info("Loop range does not fit the loaded video; playing the full video")
                return (source, nil)
            }
            let composition = AVMutableComposition()
            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { return (source, nil) }
            try compositionTrack.insertTimeRange(range, of: track, at: .zero)
            // Without the source transform, rotated videos play sideways.
            compositionTrack.preferredTransform = transform
            guard let playable = composition.copy() as? AVComposition else { return (source, nil) }
            return (playable, trim)
        } catch {
            Log.video.error("Loop range could not be built; playing the full video: \(error.localizedDescription, privacy: .public)")
            return (source, nil)
        }
    }
}

/// A trim edit made while a renderer was paused. It waits for the next
/// resume, so a paused display keeps its frame and its Paused status.
struct PendingTrimReload {
    let trim: PlaybackTrim?
}
