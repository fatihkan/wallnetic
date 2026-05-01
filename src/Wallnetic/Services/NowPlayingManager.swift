import Foundation
import SwiftUI
import AppKit

/// Reads system Now Playing info via multiple strategies:
/// 1. MRMediaRemote private framework notifications (works with proper signing)
/// 2. DistributedNotificationCenter (Apple Music, Spotify — always works)
/// 3. MRMediaRemote polling (fallback, backs off if framework is denied)
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
    @Published var appName: String = ""

    private var timer: Timer?
    private var bundle: CFBundle?
    private var mrAvailable = false
    private var consecutiveEmptyPolls: Int = 0

    // MRMediaRemote function types
    private typealias GetNowPlayingInfo = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias GetNowPlayingIsPlaying = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias SendCommand = @convention(c) (Int, [AnyHashable: Any]?) -> Bool
    private typealias RegisterNotifications = @convention(c) (DispatchQueue) -> Void
    private typealias GetNowPlayingApp = @convention(c) (DispatchQueue, @escaping (Bundle?) -> Void) -> Void

    private var getInfo: GetNowPlayingInfo?
    private var getIsPlaying: GetNowPlayingIsPlaying?
    private var sendCommand: SendCommand?
    private var registerNotifications: RegisterNotifications?
    private var getNowPlayingApp: GetNowPlayingApp?

    private init() {
        loadFramework()
    }

    // MARK: - Framework Loading

    /// MRMediaRemote is a private framework — loading it triggers App Store
    /// static-analysis rejection. We gate the entire framework path behind
    /// `#if DEBUG` so release builds rely solely on the public
    /// `DistributedNotificationCenter` fallback (Apple Music + Spotify).
    private func loadFramework() {
        #if DEBUG
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
        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteRegisterForNowPlayingNotifications" as CFString) {
            registerNotifications = unsafeBitCast(ptr, to: RegisterNotifications.self)
        }
        #endif
    }

    // MARK: - Start / Stop

    func start() {
        guard timer == nil else { return }
        isEnabled = true
        consecutiveEmptyPolls = 0

        #if DEBUG
        // Register for MRMediaRemote notifications (system-level).
        registerNotifications?(DispatchQueue.main)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mrInfoDidChange),
            name: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mrInfoDidChange),
            name: NSNotification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"),
            object: nil
        )
        #endif

        // Distributed notifications — always works, no signing required.
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(musicAppInfoChanged(_:)),
                        name: NSNotification.Name("com.apple.Music.playerInfo"), object: nil)
        dnc.addObserver(self, selector: #selector(spotifyInfoChanged(_:)),
                        name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"), object: nil)

        #if DEBUG
        // Slow poll as fallback for MRMediaRemote direct queries.
        pollMR()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.pollMR()
        }
        #endif
    }

    func stop() {
        isEnabled = false
        timer?.invalidate()
        timer = nil
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        hasTrack = false
    }

    // MARK: - MRMediaRemote notification callback

    #if DEBUG
    @objc private func mrInfoDidChange() {
        pollMR()
    }

    // MARK: - MRMediaRemote polling

    private func pollMR() {
        guard let getInfo = getInfo else { return }
        getInfo(DispatchQueue.main) { [weak self] info in
            self?.applyMR(info: info)
        }
        getIsPlaying?(DispatchQueue.main) { [weak self] playing in
            self?.isPlaying = playing
        }
    }

    private func applyMR(info: [String: Any]) {
        let newTitle = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""

        if newTitle.isEmpty {
            consecutiveEmptyPolls += 1
            if consecutiveEmptyPolls > 10, let t = timer, t.timeInterval < 30 {
                timer?.invalidate()
                timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                    self?.pollMR()
                }
            }
            return
        }

        // MRMediaRemote returned data — use it.
        consecutiveEmptyPolls = 0
        if let t = timer, t.timeInterval > 5 {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                self?.pollMR()
            }
        }

        mrAvailable = true
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
        hasTrack = true

        if titleChanged, let data = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
            artwork = NSImage(data: data)
        }
    }
    #endif

    // MARK: - Apple Music (distributed notification)

    @objc private func musicAppInfoChanged(_ note: Notification) {
        guard !mrAvailable else { return }
        guard let info = note.userInfo else { return }

        let state = info["Player State"] as? String ?? ""
        isPlaying = (state == "Playing")

        let newTitle = info["Name"] as? String ?? ""
        guard !newTitle.isEmpty else {
            if state == "Stopped" { hasTrack = false }
            return
        }

        let titleChanged = newTitle != title
        title = newTitle
        artist = info["Artist"] as? String ?? ""
        album = info["Album"] as? String ?? ""
        duration = info["Total Time"] as? Double ?? 0
        if duration > 1000 { duration /= 1000 } // Music.app reports ms
        elapsed = 0
        hasTrack = true
        appName = "Music"

        if titleChanged {
            fetchMusicArtwork(for: newTitle, artist: artist)
        }
    }

    // MARK: - Spotify (distributed notification)

    @objc private func spotifyInfoChanged(_ note: Notification) {
        guard !mrAvailable else { return }
        guard let info = note.userInfo else { return }

        let state = info["Player State"] as? String ?? ""
        isPlaying = (state == "Playing")

        let newTitle = info["Name"] as? String ?? ""
        guard !newTitle.isEmpty else {
            if state == "Stopped" { hasTrack = false }
            return
        }

        let titleChanged = newTitle != title
        title = newTitle
        artist = info["Artist"] as? String ?? ""
        album = info["Album"] as? String ?? ""
        duration = (info["Duration"] as? Double ?? 0) / 1000 // Spotify reports ms
        elapsed = 0
        hasTrack = true
        appName = "Spotify"

        if titleChanged, let artURL = info["Album Art URL"] as? String ?? info["artUrl"] as? String,
           let url = URL(string: artURL) {
            fetchArtwork(from: url)
        }
    }

    // MARK: - Artwork helpers

    private func fetchMusicArtwork(for track: String, artist: String) {
        let script = """
        tell application "Music"
            if player state is playing then
                set artData to raw data of artwork 1 of current track
                return artData
            end if
        end tell
        """
        DispatchQueue.global(qos: .utility).async { [weak self] in
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                let result = appleScript.executeAndReturnError(&error)
                let data = result.data
                if let image = NSImage(data: data) {
                    DispatchQueue.main.async { self?.artwork = image }
                }
            }
        }
    }

    private func fetchArtwork(from url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async { self?.artwork = image }
        }.resume()
    }

    // MARK: - Commands

    private enum Command: Int {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case next = 4
        case previous = 5
    }

    func togglePlayPause() {
        #if DEBUG
        _ = sendCommand?(Command.togglePlayPause.rawValue, nil)
        #endif
    }

    func next() {
        #if DEBUG
        _ = sendCommand?(Command.next.rawValue, nil)
        #endif
    }

    func previous() {
        #if DEBUG
        _ = sendCommand?(Command.previous.rawValue, nil)
        #endif
    }
}
