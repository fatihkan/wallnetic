import Foundation
import CoreMedia

/// Size and modification date of a video file. A stored loop range applies
/// only while its file still matches, so a different file at the same path
/// does not inherit it.
struct VideoFileFingerprint: Codable, Equatable {
    let byteSize: Int64
    let modificationDate: Date

    init(byteSize: Int64, modificationDate: Date) {
        self.byteSize = byteSize
        self.modificationDate = modificationDate
    }

    /// Nil when the file cannot be read. Uses file attributes, which are not
    /// cached, so a file replaced a moment ago reads as a different file.
    init?(fileAt url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              let date = attributes[.modificationDate] as? Date else { return nil }
        self.init(byteSize: size.int64Value, modificationDate: date)
    }
}

enum PlaybackTrimError: Error, Equatable {
    case invalidTime
    case outsideVideo
    case tooShort
}

/// The part of a video the wallpaper loops. Start is the first frame shown;
/// End is exclusive: the start of the first excluded frame, or the end of the
/// track. Both are exact times in the file's own timeline. The original file
/// is never modified; the range plays through a passthrough composition.
struct PlaybackTrim: Equatable {
    static let minimumLength = CMTime(value: 1, timescale: 1)
    /// Precise and approximate duration loads of one file can differ by a
    /// fraction of a frame. An End this close past the track end is clamped.
    static let endTolerance = CMTime(value: 1, timescale: 100)

    let start: CMTime
    let end: CMTime
    let fingerprint: VideoFileFingerprint

    /// The trim to store for a selection in a video of `duration`, or nil for
    /// the whole video: a full-length selection stores no trim.
    static func selection(start: CMTime, end: CMTime, duration: CMTime,
                          fingerprint: VideoFileFingerprint) throws -> PlaybackTrim? {
        guard start.isNumeric, end.isNumeric, duration.isNumeric, duration > .zero else {
            throw PlaybackTrimError.invalidTime
        }
        guard start >= .zero, end <= duration, start < end else { throw PlaybackTrimError.outsideVideo }
        if start == .zero && end == duration { return nil }
        guard end - start >= minimumLength else { throw PlaybackTrimError.tooShort }
        return PlaybackTrim(start: start, end: end, fingerprint: fingerprint)
    }

    func matches(_ fingerprint: VideoFileFingerprint?) -> Bool {
        fingerprint == self.fingerprint
    }

    /// The source range to play for a video track spanning `trackRange`, or
    /// nil when this trim does not fit that track. The full video then plays.
    func timeRange(within trackRange: CMTimeRange) -> CMTimeRange? {
        guard start.isNumeric, end.isNumeric, trackRange.isValid, !trackRange.isEmpty,
              trackRange.start.isNumeric, trackRange.end.isNumeric else { return nil }
        guard start >= trackRange.start, end <= trackRange.end + Self.endTolerance else { return nil }
        let clampedEnd = min(end, trackRange.end)
        guard clampedEnd - start >= Self.minimumLength else { return nil }
        return Self.range(from: start, to: clampedEnd, notAfter: trackRange.end)
    }

    /// A range from `start` to `end`. `CMTimeRange` stores a duration, which
    /// is rounded when the two timescales cannot be combined exactly (say
    /// nanoseconds and 1/600 s), so the end can land a tick past `limit`;
    /// then the range is shortened by that tick.
    static func range(from start: CMTime, to end: CMTime, notAfter limit: CMTime) -> CMTimeRange {
        let range = CMTimeRange(start: start, end: end)
        guard range.end > limit, range.duration.value > 1 else { return range }
        return CMTimeRange(start: start, duration: range.duration - CMTime(value: 1, timescale: range.duration.timescale))
    }

    /// `time` moved to a frame boundary (the nearest one by default) of a
    /// track whose frames last `frameDuration`, counted from `origin` (the
    /// track start).
    static func aligned(_ time: CMTime, frameDuration: CMTime, origin: CMTime = .zero,
                        rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> CMTime {
        guard time.isNumeric, origin.isNumeric, frameDuration.isNumeric, frameDuration > .zero else {
            return time
        }
        var position = (time - origin).seconds / frameDuration.seconds
        // A time already on the grid stays there despite floating-point error,
        // also when rounding up or down.
        if abs(position - position.rounded()) < 1e-6 { position = position.rounded() }
        var frames = position.rounded(rule)
        guard frames.isFinite, abs(frames) < Double(Int32.max) else { return time }
        func boundary(_ count: Double) -> CMTime {
            origin + CMTimeMultiply(frameDuration, multiplier: Int32(count))
        }
        // The snap above must not leave a result on the wrong side of `time`
        // (fine timescales, such as nanoseconds, can round into it).
        if rule == .down, boundary(frames) > time { frames -= 1 }
        if rule == .up, boundary(frames) < time { frames += 1 }
        return boundary(frames)
    }
}

/// Stored as exact integer times. `CMTime` is not `Codable`, and a decoded
/// range that is not a valid forward range is rejected as unreadable data.
extension PlaybackTrim: Codable {
    private enum CodingKeys: String, CodingKey {
        case startValue, startTimescale, endValue, endTimescale, fingerprint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = CMTime(value: try container.decode(Int64.self, forKey: .startValue),
                       timescale: try container.decode(Int32.self, forKey: .startTimescale))
        end = CMTime(value: try container.decode(Int64.self, forKey: .endValue),
                     timescale: try container.decode(Int32.self, forKey: .endTimescale))
        fingerprint = try container.decode(VideoFileFingerprint.self, forKey: .fingerprint)
        guard start.isNumeric, end.isNumeric, start >= .zero, start < end else {
            throw DecodingError.dataCorruptedError(forKey: .endValue, in: container,
                                                   debugDescription: "Not a forward time range")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start.value, forKey: .startValue)
        try container.encode(start.timescale, forKey: .startTimescale)
        try container.encode(end.value, forKey: .endValue)
        try container.encode(end.timescale, forKey: .endTimescale)
        try container.encode(fingerprint, forKey: .fingerprint)
    }
}
