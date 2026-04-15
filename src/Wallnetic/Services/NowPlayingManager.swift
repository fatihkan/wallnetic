import Foundation
import SwiftUI
import AppKit

/// Reads system Now Playing info via the private MediaRemote framework.
///
/// Private API — works on direct-distribution builds. Inside a sandboxed
/// App Store build these Mach lookups are denied, so the manager will
/// simply never publish a track and the overlay will stay hidden.
final class NowPlayingManager: ObservableObject {
    static let shared = NowPlayingManager()

    @AppStorage("nowPlaying.enabled") var isEnabled: Bool = false

    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var album: String = ""
    @Published var artwork: NSImage?
    @Published var isPlaying: Bool = false
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0
    @Published var hasTrack: Bool = false

    private var timer: Timer?
    private var bundle: CFBundle?

    private typealias GetNowPlayingInfo = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias GetNowPlayingIsPlaying = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias SendCommand = @convention(c) (Int, [AnyHashable: Any]?) -> Bool

    private var getInfo: GetNowPlayingInfo?
    private var getIsPlaying: GetNowPlayingIsPlaying?
    private var sendCommand: SendCommand?

    private init() {
        loadFramework()
    }

    // MARK: - Framework Loading

    private func loadFramework() {
        let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, url as CFURL) else { return }
        self.bundle = bundle

        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString) {
            getInfo = unsafeBitCast(ptr, to: GetNowPlayingInfo.self)
        }
        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying" as CFString) {
            getIsPlaying = unsafeBitCast(ptr, to: GetNowPlayingIsPlaying.self)
        }
        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) {
            sendCommand = unsafeBitCast(ptr, to: SendCommand.self)
        }
    }

    // MARK: - Polling

    func start() {
        guard timer == nil else { return }
        isEnabled = true
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        isEnabled = false
        timer?.invalidate()
        timer = nil
        hasTrack = false
    }

    private func poll() {
        guard let getInfo = getInfo else { return }
        getInfo(DispatchQueue.main) { [weak self] info in
            self?.apply(info: info)
        }
        getIsPlaying?(DispatchQueue.main) { [weak self] playing in
            self?.isPlaying = playing
        }
    }

    private func apply(info: [String: Any]) {
        let newTitle = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
        let newArtist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
        let newAlbum = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
        let newElapsed = info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0
        let newDuration = info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0

        let titleChanged = newTitle != title || newArtist != artist
        title = newTitle
        artist = newArtist
        album = newAlbum
        elapsed = newElapsed
        duration = newDuration
        hasTrack = !newTitle.isEmpty

        if titleChanged, let data = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
            artwork = NSImage(data: data)
        } else if newTitle.isEmpty {
            artwork = nil
        }
    }

    // MARK: - Commands

    private enum Command: Int {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case next = 4
        case previous = 5
    }

    func togglePlayPause() { _ = sendCommand?(Command.togglePlayPause.rawValue, nil) }
    func next() { _ = sendCommand?(Command.next.rawValue, nil) }
    func previous() { _ = sendCommand?(Command.previous.rawValue, nil) }
}
