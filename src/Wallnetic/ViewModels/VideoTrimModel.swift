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
    /// Each frame's start in the file's timeline, in order, when the track can
    /// list them. Start and End then snap to real frames, also for variable
    /// frame rates; otherwise they snap to a grid of the shortest frame.
    private(set) var frameStarts: [CMTime]?
    /// Valid End positions: every later frame start, then the video's end.
    private var endBoundaries: [CMTime] = []
    /// The item's own duration. It can end slightly before the video track,
    /// and the preview looper's range must stay inside it.
    private var itemDuration: CMTime = .zero
    private var fingerprint: VideoFileFingerprint?
    private var asset: AVURLAsset?
    private var looper: AVPlayerLooper?
    private var looperStatus: NSKeyValueObservation?
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
    var hasExactFrames: Bool { frameStarts != nil }
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
            itemDuration = try await asset.load(.duration)
            let layout = await FrameBoundaries.layout(of: track)
            let starts = layout?.frameStarts.filter { $0 >= range.start && $0 < range.end }
            frameStarts = starts?.isEmpty == false ? starts : nil
            self.asset = asset
            self.fingerprint = fingerprint
            origin = frameStarts?.first ?? range.start
            duration = range.end
            // An empty edit's start ends the content before it, so it is a
            // valid End even though no frame starts there.
            let ends = ((frameStarts ?? []) + (layout?.gapStarts ?? [])).filter { $0 > origin && $0 < duration }
            endBoundaries = FrameBoundaries.unique(ends.sorted()) + [duration]
            start = origin
            end = duration
            if let stored = store.trim(for: url) {
                if stored.matches(fingerprint), stored.timeRange(within: range) != nil {
                    // The stored times themselves: a range's computed end can
                    // be rounded when the two timescales differ.
                    start = stored.start
                    end = min(stored.end, duration)
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
        if let starts = frameStarts {
            let latest = FrameBoundaries.last(notAfter: end - minimumLength, in: starts) ?? origin
            start = max(origin, min(FrameBoundaries.nearest(to: time, in: starts) ?? origin, latest))
        } else {
            let latest = PlaybackTrim.aligned(end - minimumLength, frameDuration: frameDuration, origin: origin, rule: .down)
            let candidate = PlaybackTrim.aligned(time, frameDuration: frameDuration, origin: origin)
            start = max(origin, min(candidate, latest))
        }
        error = nil
        schedulePreview()
    }

    /// Moves End to the frame boundary nearest `time`, or to the end of the
    /// video, keeping at least the minimum length after Start.
    func setEnd(_ time: CMTime) {
        guard state == .ready, time.isNumeric else { return }
        if frameStarts != nil {
            let earliest = FrameBoundaries.first(notBefore: start + minimumLength, in: endBoundaries) ?? duration
            end = min(duration, max(FrameBoundaries.nearest(to: time, in: endBoundaries) ?? duration, earliest))
        } else {
            let earliest = min(duration, PlaybackTrim.aligned(start + minimumLength, frameDuration: frameDuration,
                                                              origin: origin, rule: .up))
            let aligned = PlaybackTrim.aligned(time, frameDuration: frameDuration, origin: origin)
            end = min(duration, max(aligned >= duration ? duration : aligned, earliest))
        }
        error = nil
        schedulePreview()
    }

    func stepStart(frames: Int) {
        guard let starts = frameStarts else {
            setStart(start + CMTimeMultiply(frameDuration, multiplier: Int32(frames)))
            return
        }
        let index = FrameBoundaries.nearestIndex(to: start, in: starts) ?? 0
        setStart(starts[min(max(index + frames, 0), starts.count - 1)])
    }

    func stepEnd(frames: Int) {
        guard frameStarts != nil else {
            // The track end can fall between grid points; step from the grid.
            let base = PlaybackTrim.aligned(end, frameDuration: frameDuration, origin: origin, rule: .up)
            setEnd(base + CMTimeMultiply(frameDuration, multiplier: Int32(frames)))
            return
        }
        let index = FrameBoundaries.nearestIndex(to: end, in: endBoundaries) ?? endBoundaries.count - 1
        setEnd(endBoundaries[min(max(index + frames, 0), endBoundaries.count - 1)])
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
        looperStatus = nil
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
        guard state == .ready, let asset,
              let range = Self.previewRange(start: start, end: end, itemDuration: itemDuration) else { return }
        looperStatus = nil
        looper?.disableLooping()
        player.removeAllItems()
        let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset), timeRange: range)
        looperStatus = looper.observe(\.status, options: [.initial, .new]) { [weak self] looper, _ in
            guard looper.status == .failed else { return }
            Task { @MainActor [weak self] in self?.isPreviewPlaying = false }
        }
        self.looper = looper
        player.play()
        isPreviewPlaying = true
    }

    /// The looper's range must lie within the item's duration, which can end
    /// slightly before the video track (some fragmented MP4 files). Nil for a
    /// range the looper cannot play.
    static func previewRange(start: CMTime, end: CMTime, itemDuration: CMTime) -> CMTimeRange? {
        guard start.isNumeric, end.isNumeric, itemDuration.isNumeric else { return nil }
        let previewEnd = min(end, itemDuration)
        guard start >= .zero, start < previewEnd else { return nil }
        return PlaybackTrim.range(from: start, to: previewEnd, notAfter: itemDuration)
    }

    // MARK: - Time text

    /// Minutes and seconds, rounded to hundredths first so 59.997 s reads
    /// 1:00.00 rather than 0:60.00.
    private static func minutesAndSeconds(_ time: CMTime) -> (minutes: Int, seconds: Double) {
        let hundredths = Int((max(0, time.seconds) * 100).rounded())
        return (hundredths / 6000, Double(hundredths % 6000) / 100)
    }

    /// "1:02.40": minutes, seconds and hundredths.
    static func clockText(_ time: CMTime) -> String {
        guard time.isNumeric else { return "--:--" }
        let parts = minutesAndSeconds(time)
        return String(format: "%d:%05.2f", parts.minutes, parts.seconds)
    }

    /// "1 minute 2.40 seconds", for VoiceOver.
    static func spokenText(_ time: CMTime) -> String {
        guard time.isNumeric else { return "unknown" }
        let parts = minutesAndSeconds(time)
        let seconds = String(format: "%.2f seconds", parts.seconds)
        guard parts.minutes > 0 else { return seconds }
        return "\(parts.minutes) \(parts.minutes == 1 ? "minute" : "minutes") \(seconds)"
    }
}

/// Frame boundaries of a video track, and lookups over sorted times.
enum FrameBoundaries {
    /// Where a track's frames start in its timeline, and where its empty
    /// edits (gaps) start. A gap's start ends the content before it, so it is
    /// a valid End but not a Start.
    struct Layout: Equatable {
        var frameStarts: [CMTime]
        var gapStarts: [CMTime]
    }

    /// One edit of a track: how it maps media time into the track, or a gap.
    struct Edit {
        let mapping: CMTimeMapping
        let isEmpty: Bool
    }

    /// The track's layout from a sample cursor and its edits. Nil when the
    /// track cannot provide cursors, has more than `limit` frames, or uses an
    /// edit that changes speed.
    static func layout(of track: AVAssetTrack, limit: Int = 200_000) async -> Layout? {
        guard (try? await track.load(.canProvideSampleCursors)) == true,
              let segments = try? await track.load(.segments),
              let cursor = track.makeSampleCursor(presentationTimeStamp: .negativeInfinity) else { return nil }
        var media: [CMTime] = []
        repeat {
            guard media.count < limit else { return nil }
            media.append(cursor.presentationTimeStamp)
        } while cursor.stepInPresentationOrder(byCount: 1) == 1
        return layout(ofMediaTimes: media, edits: segments.map { Edit(mapping: $0.timeMapping, isEmpty: $0.isEmpty) })
    }

    /// Media sample times mapped into the track's timeline through its edits.
    /// An edit that starts partway through a sample shows that sample from the
    /// edit's start, so the edit's start is a frame start too.
    static func layout(ofMediaTimes media: [CMTime], edits: [Edit]) -> Layout? {
        let samples = media.filter(\.isNumeric).sorted()
        var starts: [CMTime] = []
        var gaps: [CMTime] = []
        if edits.isEmpty { starts = samples }
        for edit in edits {
            let source = edit.mapping.source, target = edit.mapping.target
            guard target.start.isNumeric else { continue }
            if edit.isEmpty {
                gaps.append(target.start)
                continue
            }
            // Only an edit that keeps speed maps a frame's start exactly.
            guard source.duration == target.duration else { return nil }
            if let first = samples.first, first <= source.start { starts.append(target.start) }
            for time in samples where time > source.start && time < source.end {
                starts.append(target.start + (time - source.start))
            }
        }
        let frameStarts = unique(starts.sorted())
        guard let firstFrame = frameStarts.first else { return nil }
        return Layout(frameStarts: frameStarts, gapStarts: unique(gaps.filter { $0 > firstFrame }.sorted()))
    }

    static func unique(_ sorted: [CMTime]) -> [CMTime] {
        var result: [CMTime] = []
        for time in sorted where result.last.map({ $0 != time }) ?? true { result.append(time) }
        return result
    }

    static func nearestIndex(to time: CMTime, in sorted: [CMTime]) -> Int? {
        guard !sorted.isEmpty, time.isNumeric else { return nil }
        let index = firstIndex(notBefore: time, in: sorted)
        if index == 0 { return 0 }
        if index == sorted.count { return sorted.count - 1 }
        return time - sorted[index - 1] <= sorted[index] - time ? index - 1 : index
    }

    static func nearest(to time: CMTime, in sorted: [CMTime]) -> CMTime? {
        nearestIndex(to: time, in: sorted).map { sorted[$0] }
    }

    static func first(notBefore time: CMTime, in sorted: [CMTime]) -> CMTime? {
        let index = firstIndex(notBefore: time, in: sorted)
        return index < sorted.count ? sorted[index] : nil
    }

    static func last(notAfter time: CMTime, in sorted: [CMTime]) -> CMTime? {
        var low = 0, high = sorted.count
        while low < high {
            let middle = (low + high) / 2
            if sorted[middle] <= time { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? sorted[low - 1] : nil
    }

    private static func firstIndex(notBefore time: CMTime, in sorted: [CMTime]) -> Int {
        var low = 0, high = sorted.count
        while low < high {
            let middle = (low + high) / 2
            if sorted[middle] < time { low = middle + 1 } else { high = middle }
        }
        return low
    }
}
