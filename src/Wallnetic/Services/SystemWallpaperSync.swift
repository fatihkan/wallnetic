import AppKit
import AVFoundation
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
/// configured in System Settings. Playing actual video on the lock screen
/// is not possible for third-party apps (it lives in a separate secure
/// session), so a matching still frame is the best the platform allows.
@MainActor
final class SystemWallpaperSync: ObservableObject {
    static let shared = SystemWallpaperSync()

    @AppStorage("systemsync.enabled") var isEnabled: Bool = true
    /// First-seen system wallpaper per screen (localizedName → path) so
    /// disabling the feature can restore what the user had before.
    @AppStorage("systemsync.originalsJSON") private var originalsJSON: String = "{}"

    private var observers: [Any] = []
    private var workspaceObserver: Any?
    /// Last frame applied per screen (localizedName → frame URL).
    private var appliedFrames: [String: URL] = [:]
    /// Video URLs with an extraction currently in flight (dedup guard for
    /// rapid changes — slideshow, per-Space switching).
    private var inFlight: Set<URL> = []
    private var started = false

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
    }

    /// Full sync of the current wallpaper(s) — used when the toggle flips on.
    func syncNow() {
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
            guard let path = originals[screen.localizedName],
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
    }

    // MARK: - Sync

    private func sync(videoURL: URL, to screens: [NSScreen]) {
        guard videoURL.isFileURL else { return }

        let frameURL = Self.framesDirectory()
            .appendingPathComponent(Self.frameFileName(for: videoURL))

        if FileManager.default.fileExists(atPath: frameURL.path) {
            apply(frameURL: frameURL, to: screens)
            return
        }

        guard !inFlight.contains(videoURL) else { return }
        inFlight.insert(videoURL)

        // Largest backing size among target screens bounds the extraction.
        let maxSize = screens.reduce(CGSize(width: 1920, height: 1080)) { acc, screen in
            let px = CGSize(width: screen.frame.width * screen.backingScaleFactor,
                            height: screen.frame.height * screen.backingScaleFactor)
            return px.width * px.height > acc.width * acc.height ? px : acc
        }
        // Only immutable Sendable values cross the await (Xcode 15.2 WMO).
        let screenNames = screens.map(\.localizedName)

        Task { [weak self] in
            let extracted = await Self.extractFrame(videoURL: videoURL, maxSize: maxSize, to: frameURL)
            guard let self else { return }
            self.inFlight.remove(videoURL)
            guard extracted, self.isEnabled else { return }
            let targets = NSScreen.screens.filter { screenNames.contains($0.localizedName) }
            self.apply(frameURL: frameURL, to: targets)
            Self.cleanupFrames(in: Self.framesDirectory(), keepingNewest: 8)
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
            do {
                try NSWorkspace.shared.setDesktopImageURL(frameURL, for: screen, options: options)
                appliedFrames[screen.localizedName] = frameURL
            } catch {
                Log.sysWallpaper.error("setDesktopImageURL failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Spaces and freshly connected displays may still show a stale picture
    /// — push the last frame wherever the OS reports something else.
    private func reapplyIfNeeded() {
        guard isEnabled else { return }
        for screen in NSScreen.screens {
            guard let frameURL = appliedFrames[screen.localizedName],
                  NSWorkspace.shared.desktopImageURL(for: screen) != frameURL else { continue }
            apply(frameURL: frameURL, to: [screen])
        }
    }

    private func backupOriginalsIfNeeded(screens: [NSScreen]) {
        var originals = Self.decodeOriginals(originalsJSON)
        var changed = false
        let framesDir = Self.framesDirectory().path
        for screen in screens {
            let key = screen.localizedName
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
        videoURL: URL, maxSize: CGSize, to destination: URL
    ) async -> Bool {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize
        // Default (loose) tolerances: keyframe-aligned and fast.

        do {
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            let time = CMTime(seconds: frameTime(forDuration: duration), preferredTimescale: 600)
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
    /// whenever the video actually changes.
    nonisolated static func frameFileName(for videoURL: URL) -> String {
        let digest = SHA256.hash(data: Data(videoURL.path.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined().prefix(16)
        return "frame-\(hex).jpg"
    }

    nonisolated static func framesDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Wallnetic/SystemWallpaper", isDirectory: true)
    }

    /// Caps the frame cache, dropping the oldest files first.
    nonisolated static func cleanupFrames(in directory: URL, keepingNewest keep: Int) {
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
        for url in sorted.dropFirst(keep) {
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
