import AppKit
import AVFoundation
import Combine
import CryptoKit
import Foundation
import SwiftUI

/// Keeps the *system* wallpaper in sync with a still frame of the current
/// video wallpaper.
///
/// macOS renders the system wallpaper — not app windows — on the lock
/// screen, in Mission Control Space previews, and during Space transition
/// animations. Wallnetic draws video in its own desktop-level window, so
/// without this sync those surfaces show whatever unrelated picture is
/// configured in System Settings. The documented API used here sets an image;
/// it does not register a live lock-screen background. The OS controls how that
/// image appears on each surface. See docs/SCREENSAVER_FEASIBILITY.md (#259).
@MainActor
final class SystemWallpaperSync: ObservableObject {
    static let shared = SystemWallpaperSync()

    @AppStorage("systemsync.enabled") var isEnabled: Bool = true
    /// First-seen system wallpaper per display (stringified CGDirectDisplayID
    /// → path) so disabling the feature can restore what the user had before.
    @AppStorage("systemsync.originalsJSON") private var originalsJSON: String = "{}"

    private var observers: [Any] = []
    private var workspaceObserver: Any?
    /// Last frame applied per display (CGDirectDisplayID → frame URL). Keyed
    /// by display id, not localizedName, so identical monitors don't collide.
    private var appliedFrames: [CGDirectDisplayID: URL] = [:]
    /// Extractions in flight, by still file (video and loop range), with the
    /// displays waiting for each. A later request for the same still joins
    /// them instead of starting a second extraction (slideshow, per-Space
    /// switching, two displays showing one video).
    private var inFlight: [URL: Set<CGDirectDisplayID>] = [:]
    /// The still each display asked for last, and the video it came from. A
    /// finished extraction applies only to displays that still want it, and a
    /// range edit resyncs the displays whose video it changed.
    private var requestedFrames: [CGDirectDisplayID: URL] = [:]
    private var syncedVideos: [CGDirectDisplayID: URL] = [:]
    private var started = false
    /// Loop ranges as of the last sync, to resync only the edited videos.
    private var syncedTrims: [String: PlaybackTrim] = [:]
    private var trimObserver: AnyCancellable?

    private init() {}

    // MARK: - Lifecycle

    /// Registers observers. Called once at launch *before* WallpaperManager
    /// restores the last wallpaper, so the restore triggers the first sync.
    func start() {
        guard !started else { return }
        started = true

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .wallpaperDidChange, object: nil, queue: .main
        ) { [weak self] note in
            guard let wp = note.object as? Wallpaper else { return }
            // Explicit capture list — Xcode 15.2 (Swift 5.9) rejects the
            // implicit capture of the outer weak `self` inside the Task.
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled else { return }
                // Per-screen mode posts .screenWallpaperDidChange for the
                // concrete screen; reacting here too would fan the active
                // screen's frame out to every display.
                guard WallpaperManager.shared.wallpaperMode == .same else { return }
                self.sync(videoURL: wp.url, to: NSScreen.screens)
            }
        })
        observers.append(center.addObserver(
            forName: .screenWallpaperDidChange, object: nil, queue: .main
        ) { [weak self] note in
            guard let info = note.object as? ScreenWallpaperInfo else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled else { return }
                self.sync(videoURL: info.wallpaper.url, to: [info.screen])
            }
        })
        // Each Space keeps its own system wallpaper: re-apply when the user
        // lands on a Space that still shows a stale/default picture.
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reapplyIfNeeded() }
        }
        // Freshly connected displays start with the system default.
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reapplyIfNeeded() }
        })
        // A loop-range edit changes which still belongs to that video. It is
        // not a wallpaper change, so it does not repost .wallpaperDidChange.
        syncedTrims = PlaybackTrimStore.shared.trims
        trimObserver = PlaybackTrimStore.shared.$trims.dropFirst().sink { [weak self] trims in
            Task { @MainActor [weak self] in self?.resyncEditedRanges(trims) }
        }
    }

    /// Resyncs only the displays showing a video whose range was added,
    /// edited or removed.
    private func resyncEditedRanges(_ trims: [String: PlaybackTrim]) {
        let changed = Set(trims.keys).union(syncedTrims.keys).filter { trims[$0] != syncedTrims[$0] }
        syncedTrims = trims
        guard isEnabled, !changed.isEmpty else { return }
        // The displays playing an edited video now. Cleared displays play
        // nothing and keep their still.
        let videos = (playingVideos() ?? syncedVideos).filter { changed.contains($0.value.standardizedFileURL.path) }
        syncGrouped(videos)
    }

    /// What each connected display plays now, from the desktop windows. Nil
    /// when playback is not connected; this service's own sync history is
    /// then the best guess.
    private func playingVideos() -> [CGDirectDisplayID: URL]? {
        guard let playback = WallpaperManager.shared.playbackDelegate else { return nil }
        var videos: [CGDirectDisplayID: URL] = [:]
        for screen in NSScreen.screens {
            if let id = screen.displayID, let url = playback.playbackWallpaperURL(on: id) { videos[id] = url }
        }
        return videos
    }

    /// Syncs displays grouped by video, so each still is extracted once for
    /// all displays showing it.
    private func syncGrouped(_ videos: [CGDirectDisplayID: URL]) {
        var screensByVideo: [URL: [NSScreen]] = [:]
        for screen in NSScreen.screens {
            guard let id = screen.displayID, let video = videos[id] else { continue }
            screensByVideo[video, default: []].append(screen)
        }
        for (video, screens) in screensByVideo {
            sync(videoURL: video, to: screens)
        }
    }

    /// Full sync of the current wallpaper(s) — used when the toggle flips on.
    func syncNow() {
        if let playing = playingVideos() {
            syncGrouped(playing)
            return
        }
        let manager = WallpaperManager.shared
        if manager.wallpaperMode == .different {
            for screen in NSScreen.screens {
                if let wp = manager.wallpaper(for: screen) {
                    sync(videoURL: wp.url, to: [screen])
                }
            }
        } else if let wp = manager.currentWallpaper {
            sync(videoURL: wp.url, to: NSScreen.screens)
        }
    }

    /// Puts the system wallpaper back to what it was before the first sync
    /// — used when the toggle flips off.
    func restoreOriginals() {
        let originals = Self.decodeOriginals(originalsJSON)
        for screen in NSScreen.screens {
            guard let id = screen.displayID,
                  let path = originals[String(id)],
                  FileManager.default.fileExists(atPath: path) else { continue }
            do {
                try NSWorkspace.shared.setDesktopImageURL(
                    URL(fileURLWithPath: path), for: screen, options: [:]
                )
            } catch {
                Log.sysWallpaper.error("Restore failed: \(String(describing: error), privacy: .public)")
            }
        }
        originalsJSON = "{}"
        appliedFrames.removeAll()
        requestedFrames.removeAll()
        syncedVideos.removeAll()
    }

    // MARK: - Sync

    private func sync(videoURL: URL, to screens: [NSScreen]) {
        guard videoURL.isFileURL else { return }

        // A trimmed video's still comes from inside its loop range.
        let trim = TrimmedVideoAsset.usableTrim(PlaybackTrimStore.shared.trim(for: videoURL), for: videoURL)
        let frameURL = Self.framesDirectory()
            .appendingPathComponent(Self.frameFileName(for: videoURL, trim: trim))
        let targetIDs = screens.compactMap(\.displayID)
        for id in targetIDs {
            requestedFrames[id] = frameURL
            syncedVideos[id] = videoURL
        }

        if FileManager.default.fileExists(atPath: frameURL.path) {
            apply(frameURL: frameURL, to: screens)
            return
        }

        if inFlight[frameURL] != nil {
            inFlight[frameURL]?.formUnion(targetIDs)
            return
        }
        inFlight[frameURL] = Set(targetIDs)

        // The largest connected display bounds the extraction, so displays
        // that join while it runs get a large enough still too.
        let maxSize = NSScreen.screens.reduce(CGSize(width: 1920, height: 1080)) { acc, screen in
            let px = CGSize(width: screen.frame.width * screen.backingScaleFactor,
                            height: screen.frame.height * screen.backingScaleFactor)
            return px.width * px.height > acc.width * acc.height ? px : acc
        }

        // Only immutable Sendable values cross the await (Xcode 15.2 WMO).
        Task { [weak self] in
            let extracted = await Self.extractFrame(videoURL: videoURL, trim: trim, maxSize: maxSize, to: frameURL)
            guard let self else { return }
            let waiting = self.inFlight.removeValue(forKey: frameURL) ?? []
            guard extracted, self.isEnabled else { return }
            // Re-resolve screens at apply time, by stable display id. A display
            // that asked for another still meanwhile (a newer range or
            // wallpaper) keeps that one.
            let targets = NSScreen.screens.filter { screen in
                guard let id = screen.displayID else { return false }
                return waiting.contains(id) && self.requestedFrames[id] == frameURL
            }
            self.apply(frameURL: frameURL, to: targets)
            // Stills in use as any display's picture stay, including ones
            // applied before this session.
            let inUse = Set(self.appliedFrames.values)
                .union(NSScreen.screens.compactMap { NSWorkspace.shared.desktopImageURL(for: $0) })
            Self.cleanupFrames(in: Self.framesDirectory(), keepingNewest: 8, protecting: inUse)
        }
    }

    private func apply(frameURL: URL, to screens: [NSScreen]) {
        backupOriginalsIfNeeded(screens: screens)
        // "Fill Screen" semantics — matches how the video itself renders.
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            .allowClipping: true
        ]
        for screen in screens {
            guard let id = screen.displayID else { continue }
            do {
                try NSWorkspace.shared.setDesktopImageURL(frameURL, for: screen, options: options)
                appliedFrames[id] = frameURL
            } catch {
                Log.sysWallpaper.error("setDesktopImageURL failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Spaces and freshly connected displays may still show a stale picture
    /// — push the last frame wherever the OS reports something else.
    private func reapplyIfNeeded() {
        guard isEnabled else { return }
        // A display connected since the last sync has no still of its own yet.
        if let playing = playingVideos() {
            syncGrouped(playing.filter { appliedFrames[$0.key] == nil })
        }
        for screen in NSScreen.screens {
            guard let id = screen.displayID,
                  let frameURL = appliedFrames[id],
                  NSWorkspace.shared.desktopImageURL(for: screen) != frameURL else { continue }
            apply(frameURL: frameURL, to: [screen])
        }
    }

    private func backupOriginalsIfNeeded(screens: [NSScreen]) {
        var originals = Self.decodeOriginals(originalsJSON)
        var changed = false
        let framesDir = Self.framesDirectory().path
        for screen in screens {
            guard let id = screen.displayID else { continue }
            let key = String(id)
            guard originals[key] == nil,
                  let current = NSWorkspace.shared.desktopImageURL(for: screen),
                  current.isFileURL,
                  !current.path.hasPrefix(framesDir) else { continue }
            originals[key] = current.path
            changed = true
        }
        if changed { originalsJSON = Self.encodeOriginals(originals) }
    }

    // MARK: - Frame Extraction

    /// Extracts a representative still and writes it as JPEG. Runs off the
    /// main actor; touches no shared state.
    nonisolated private static func extractFrame(
        videoURL: URL, trim: PlaybackTrim?, maxSize: CGSize, to destination: URL
    ) async -> Bool {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize
        // Default (loose) tolerances: keyframe-aligned and fast.

        do {
            let time: CMTime
            if let trim {
                // Offset into the loop like an untrimmed video's still, with
                // tolerances that keep the decoded frame inside the range.
                time = trim.stillFrameTime(atOffset: frameTime(forDuration: (trim.end - trim.start).seconds))
                generator.requestedTimeToleranceBefore = time - trim.start
                generator.requestedTimeToleranceAfter = max(.zero, trim.end - time - CMTime(value: 1, timescale: 600))
            } else {
                let duration = (try? await asset.load(.duration).seconds) ?? 0
                time = CMTime(seconds: frameTime(forDuration: duration), preferredTimescale: 600)
            }
            let (cgImage, _) = try await generator.image(at: time)

            let rep = NSBitmapImageRep(cgImage: cgImage)
            guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
                return false
            }
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: destination, options: .atomic)
            return true
        } catch {
            Log.sysWallpaper.error("Frame extraction failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    // MARK: - Pure Helpers (unit-tested)

    /// Picks a frame timestamp that skips fade-from-black intros without
    /// seeking deep into long videos.
    nonisolated static func frameTime(forDuration duration: Double) -> Double {
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(min(max(duration * 0.1, 0.5), 3.0), duration)
    }

    /// Stable per-video frame filename, so a video applied again later
    /// reuses its cached frame and the wallpaper agent sees a fresh URL
    /// whenever the video, or its loop range, actually changes.
    nonisolated static func frameFileName(for videoURL: URL, trim: PlaybackTrim? = nil) -> String {
        var key = videoURL.path
        if let trim {
            key += "|\(trim.start.value)/\(trim.start.timescale)-\(trim.end.value)/\(trim.end.timescale)"
        }
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined().prefix(16)
        return "frame-\(hex).jpg"
    }

    nonisolated static func framesDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Wallnetic/SystemWallpaper", isDirectory: true)
    }

    /// Caps the frame cache, dropping the oldest files first.
    /// `protecting`: stills in use as a display's wallpaper are never removed,
    /// however old, because Spaces and reconnected displays reapply them.
    nonisolated static func cleanupFrames(in directory: URL, keepingNewest keep: Int, protecting: Set<URL> = []) {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ), urls.count > keep else { return }

        let sorted = urls.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }
        let protectedPaths = Set(protecting.map { $0.standardizedFileURL.resolvingSymlinksInPath().path })
        for url in sorted.dropFirst(keep)
        where !protectedPaths.contains(url.standardizedFileURL.resolvingSymlinksInPath().path) {
            try? fm.removeItem(at: url)
        }
    }

    nonisolated static func decodeOriginals(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    nonisolated static func encodeOriginals(_ originals: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(originals),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}
