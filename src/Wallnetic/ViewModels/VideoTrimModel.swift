import Foundation
import AVFoundation

/// Whether a Library item has a loop range, and whether it can apply.
enum LoopRangeStatus: Equatable {
    case none
    case applied(PlaybackTrim)
    /// The file changed, or the range no longer fits it. The full video plays.
    case notApplied

    init(trim: PlaybackTrim?, fileAt url: URL, duration: Double?) {
        guard let trim else { self = .none; return }
        let fits = duration.map { trim.end.seconds <= $0 + PlaybackTrim.endTolerance.seconds } ?? true
        self = trim.matches(VideoFileFingerprint(fileAt: url)) && fits ? .applied(trim) : .notApplied
    }

    /// "0:42", the length of one loop, for a trimmed item.
    var loopLengthText: String? {
        guard case .applied(let trim) = self else { return nil }
        return Wallpaper.formattedDuration((trim.end - trim.start).seconds)
    }

    /// "0:42 of 1:10" for a trimmed item, or the plain duration.
    static func durationText(_ status: LoopRangeStatus, duration: Double?) -> String {
        guard let loop = status.loopLengthText else { return Wallpaper.formattedDuration(duration) }
        return "\(loop) of \(Wallpaper.formattedDuration(duration))"
    }
}

/// Draft loop range for one Library video, edited in the trim sheet. Times
/// snap to the video's frames. Saving stores the range; cancelling or closing
/// the sheet leaves the stored range unchanged.
@MainActor
final class VideoTrimModel: ObservableObject {
    enum State: Equatable {
        case loading
        case ready
        case failed(String)
    }

    let wallpaper: Wallpaper
    @Published private(set) var state: State = .loading
    @Published private(set) var start: CMTime = .zero
    @Published private(set) var end: CMTime = .zero
    /// Where the video track starts and ends in the file's timeline.
    @Published private(set) var origin: CMTime = .zero
    @Published private(set) var duration: CMTime = .zero
    @Published private(set) var note: String?
    @Published private(set) var error: String?
    @Published private(set) var isPreviewPlaying = false

    /// Muted, looping preview of the draft range.
    let player = AVQueuePlayer()
    private(set) var frameDuration = CMTime(value: 1, timescale: 30)
    private var fingerprint: VideoFileFingerprint?
    private var asset: AVURLAsset?
    private var looper: AVPlayerLooper?
    private var previewTask: Task<Void, Never>?
    private let store: PlaybackTrimStore
    private let isInLibrary: (URL) -> Bool

    init(wallpaper: Wallpaper, store: PlaybackTrimStore = .shared,
         isInLibrary: @escaping (URL) -> Bool = { url in
             WallpaperManager.shared.wallpapers.contains { $0.url.standardizedFileURL == url.standardizedFileURL }
         }) {
        self.wallpaper = wallpaper
        self.store = store
        self.isInLibrary = isInLibrary
        player.isMuted = true
    }

    var url: URL { wallpaper.url }
    var length: CMTime { end - start }
    var isFullVideo: Bool { start == origin && end == duration }
    /// The shortest range; a video shorter than that can only loop in full.
    var minimumLength: CMTime { min(PlaybackTrim.minimumLength, duration - origin) }

    func load() async {
        guard let fingerprint = VideoFileFingerprint(fileAt: url) else {
            state = .failed("The video file is missing or cannot be read.")
            return
        }
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                state = .failed("This file has no video track.")
                return
            }
            let (range, minFrameDuration, frameRate) = try await track.load(.timeRange, .minFrameDuration, .nominalFrameRate)
            guard range.isValid, !range.isEmpty, range.start.isNumeric, range.end.isNumeric else {
                state = .failed("The video's length could not be read.")
                return
            }
            if minFrameDuration.isNumeric, minFrameDuration > .zero {
                frameDuration = minFrameDuration
            } else if frameRate > 0 {
                frameDuration = CMTime(seconds: 1 / Double(frameRate), preferredTimescale: 600)
            }
            self.asset = asset
            self.fingerprint = fingerprint
            origin = range.start
            duration = range.end
            start = origin
            end = duration
            if let stored = store.trim(for: url) {
                if stored.matches(fingerprint), let fitted = stored.timeRange(within: range) {
                    start = fitted.start
                    end = fitted.end
                } else {
                    note = "The saved range does not match this file and is not applied. Saving replaces it."
                }
            }
            state = .ready
            schedulePreview(after: 0)
        } catch {
            state = .failed("The video could not be read: \(error.localizedDescription)")
        }
    }

    /// Moves Start to the frame nearest `time`, keeping at least the minimum
    /// length before End.
    func setStart(_ time: CMTime) {
        guard state == .ready, time.isNumeric else { return }
        let latest = PlaybackTrim.aligned(end - minimumLength, frameDuration: frameDuration, origin: origin, rule: .down)
        let candidate = PlaybackTrim.aligned(time, frameDuration: frameDuration, origin: origin)
        start = max(origin, min(candidate, latest))
        error = nil
        schedulePreview()
    }

    /// Moves End to the frame boundary nearest `time`, or to the end of the
    /// video, keeping at least the minimum length after Start.
    func setEnd(_ time: CMTime) {
        guard state == .ready, time.isNumeric else { return }
        let earliest = min(duration, PlaybackTrim.aligned(start + minimumLength, frameDuration: frameDuration,
                                                          origin: origin, rule: .up))
        let aligned = PlaybackTrim.aligned(time, frameDuration: frameDuration, origin: origin)
        end = min(duration, max(aligned >= duration ? duration : aligned, earliest))
        error = nil
        schedulePreview()
    }

    func stepStart(frames: Int) {
        setStart(start + CMTimeMultiply(frameDuration, multiplier: Int32(frames)))
    }

    func stepEnd(frames: Int) {
        // The track end can fall between frame boundaries; step from the grid.
        let base = PlaybackTrim.aligned(end, frameDuration: frameDuration, origin: origin, rule: .up)
        setEnd(base + CMTimeMultiply(frameDuration, multiplier: Int32(frames)))
    }

    func resetToFullVideo() {
        guard state == .ready else { return }
        start = origin
        end = duration
        error = nil
        schedulePreview()
    }

    /// Stores the draft and returns true. Stores nothing, and says why, when
    /// the item left the Library or its file changed while the sheet was open.
    func save() -> Bool {
        guard state == .ready, let fingerprint else { return false }
        guard isInLibrary(url), FileManager.default.fileExists(atPath: url.path) else {
            error = "This video is no longer in the Library, so nothing was saved."
            return false
        }
        guard VideoFileFingerprint(fileAt: url) == fingerprint else {
            error = "This video's file changed while the editor was open, so nothing was saved. Open Trim again to edit the new file."
            return false
        }
        do {
            let trim = isFullVideo ? nil : try PlaybackTrim.selection(start: start, end: end, duration: duration,
                                                                         fingerprint: fingerprint)
            try store.setTrim(trim, for: url)
            return true
        } catch PlaybackTrimError.tooShort {
            error = "A loop must be at least one second long."
        } catch is PlaybackTrimError {
            error = "Start and End must be inside the video, with Start before End."
        } catch {
            self.error = "The range could not be saved: \(error.localizedDescription)"
        }
        return false
    }

    func togglePreview() {
        if player.rate == 0 { player.play() } else { player.pause() }
        isPreviewPlaying = player.rate != 0
    }

    func stopPreview() {
        previewTask?.cancel()
        looper?.disableLooping()
        looper = nil
        player.pause()
        player.removeAllItems()
        isPreviewPlaying = false
    }

    /// Rebuilds the looping preview once edits pause. The looper raises an
    /// exception for an empty range or one outside the item, so the draft is
    /// checked first.
    private func schedulePreview(after delay: UInt64 = 300_000_000) {
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            guard !Task.isCancelled else { return }
            self?.rebuildPreview()
        }
    }

    private func rebuildPreview() {
        guard state == .ready, let asset, start >= origin, start < end, end <= duration else { return }
        looper?.disableLooping()
        player.removeAllItems()
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset),
                                timeRange: CMTimeRange(start: start, end: end))
        player.play()
        isPreviewPlaying = true
    }

    // MARK: - Time text

    /// "1:02.40": minutes, seconds and hundredths.
    static func clockText(_ time: CMTime) -> String {
        guard time.isNumeric else { return "--:--" }
        let seconds = max(0, time.seconds)
        return String(format: "%d:%05.2f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
    }

    /// "1 minute 2.40 seconds", for VoiceOver.
    static func spokenText(_ time: CMTime) -> String {
        guard time.isNumeric else { return "unknown" }
        let total = max(0, time.seconds)
        let minutes = Int(total) / 60
        let seconds = String(format: "%.2f seconds", total.truncatingRemainder(dividingBy: 60))
        guard minutes > 0 else { return seconds }
        return "\(minutes) \(minutes == 1 ? "minute" : "minutes") \(seconds)"
    }
}
