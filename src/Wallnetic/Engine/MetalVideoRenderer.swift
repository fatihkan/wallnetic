import Cocoa
import AVFoundation
import Metal
import MetalKit
import CoreVideo
import os.log

private let logger = Logger(subsystem: "com.wallnetic.app", category: "MetalVideoRenderer")

/// The display-link thread only touches this locked gate. Renderer and AppKit
/// state are accessed by the handler on the main queue, never by Core Video.
final class DisplayLinkFrameScheduler: @unchecked Sendable {
    private let lock = NSLock()
    private var isActive = true
    private var isPending = false
    private var frameInterval: TimeInterval
    private var nextFrameTime: TimeInterval?
    private let draw: () -> Void

    init(maximumFramesPerSecond: Int = 60, draw: @escaping () -> Void) {
        frameInterval = 1 / Double(max(1, maximumFramesPerSecond))
        self.draw = draw
    }

    func setMaximumFramesPerSecond(_ fps: Int) {
        lock.lock()
        defer { lock.unlock() }
        let interval = 1 / Double(max(1, fps))
        guard interval != frameInterval else { return }
        frameInterval = interval
        nextFrameTime = nil
    }

    func requestFrame(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        lock.lock()
        guard isActive, !isPending, time.isFinite else {
            lock.unlock()
            return
        }
        if let nextFrameTime, time + 0.000_001 < nextFrameTime {
            lock.unlock()
            return
        }
        // Preserve cadence across fractional refresh rates without queuing
        // catch-up frames after the display or main thread stalls.
        if let nextFrameTime, time - nextFrameTime < frameInterval {
            self.nextFrameTime = nextFrameTime + frameInterval
        } else {
            nextFrameTime = time + frameInterval
        }
        isPending = true
        lock.unlock()

        DispatchQueue.main.async { [self] in
            lock.lock()
            isPending = false
            let shouldDraw = isActive
            lock.unlock()
            if shouldDraw { draw() }
        }
    }

    /// Called on main before stopping the display link. Already queued work
    /// from this playback session must not draw after a pause or restart.
    func invalidate() {
        lock.lock()
        isActive = false
        lock.unlock()
    }
}

/// Metal-based video renderer for optimal GPU performance
/// Uses Metal directly for video frame rendering, bypassing AppKit overhead
final class MetalVideoRenderer: NSObject {

    // MARK: - Metal Objects

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState!
    private var textureCache: CVMetalTextureCache?

    // MARK: - Video Objects

    private var player: AVPlayer?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var displayLink: CVDisplayLink?
    private var frameScheduler: DisplayLinkFrameScheduler?

    // MARK: - View

    let metalView: MTKView
    // An in-flight frame can outlive the renderer. Keep its Core Video cache
    // alive as well as the texture wrapper: releasing the wrapper returns its
    // backing to that cache, including on Metal's completion queue.
    private final class VideoFrame {
        let texture: MTLTexture
        /// Display size of the video this frame came from. The crop follows
        /// the frame, so a frame kept on screen across a reload keeps its own
        /// crop until the next video's first frame replaces it (#307).
        let videoSize: CGSize
        private var backing: CVMetalTexture?
        private let cache: CVMetalTextureCache

        init(texture: MTLTexture, videoSize: CGSize, backing: CVMetalTexture, cache: CVMetalTextureCache) {
            self.texture = texture
            self.videoSize = videoSize
            self.backing = backing
            self.cache = cache
        }

        deinit {
            // Do not rely on stored-property destruction order. Core Video's
            // wrapper must be released before the last reference to its cache.
            withExtendedLifetime(cache) { backing = nil }
        }
    }
    private var currentFrame: VideoFrame?
    private var vertexBuffer: MTLBuffer?
    /// The crop `vertexBuffer` was built for: always the drawn frame's.
    private(set) var quadCrop: WallpaperFrameCrop?
    /// Display size of the current player's video, given to its frames.
    private(set) var playerVideoSize: CGSize = .zero
    private var lastPresentedSeconds: Double = -1
    private var hasLoggedFrameColorInfo = false
    private var loopObserver: NSObjectProtocol?
    /// The video and loop range of the latest load, for trim edits.
    private var loadedURL: URL?
    private var loadedTrim: PlaybackTrim?
    private var pendingTrimReload: PendingTrimReload?
    /// The load started by a trim edit, while it is the latest load.
    private var trimReloadGeneration: UInt64?
    /// The range the current player loops, or nil when it plays the full video.
    private(set) var appliedTrim: PlaybackTrim?

    // MARK: - State

    /// User/controller wants playback. Distinct from "the player exists" —
    /// `play()` used to set this true while `player` was still nil, then
    /// `setupPlayer` never started it (`guard !isPlaying`), leaving a black
    /// MTKView forever.
    private var wantsToPlay = false
    private var performanceMode: PerformanceManager.PerformanceMode = .balanced
    private let renderLock = NSLock()
    private var loadGeneration: UInt64 = 0
    private var frameGeneration: UInt64?
    private var reportedFrameGeneration: UInt64?
    private var playerGeneration: UInt64?
    private var loadTask: Task<Void, Never>?

    let playbackMonitor = RendererPlaybackMonitor()
    var hasPresentedFrame = false
    var onBecameReady: (() -> Void)?
    var filterLayer: CALayer? { metalView.layer }

    // MARK: - Vertex Data

    private struct Vertex {
        var position: SIMD4<Float>
        var texCoord: SIMD2<Float>
    }

    // MARK: - Initialization

    static var isSupported: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }

    override init() {
        // Create Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported — check MetalVideoRenderer.isSupported before init")
        }
        self.device = device

        // Create command queue
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Failed to create Metal command queue")
        }
        self.commandQueue = commandQueue

        // Create MTKView
        metalView = MTKView()
        metalView.device = device
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = true
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = false
        metalView.preferredFramesPerSecond = 60
        metalView.clearColor = MTLClearColorMake(0, 0, 0, 1)
        metalView.layer?.isOpaque = true

        // Create texture cache
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        self.textureCache = cache

        // Create pipeline state with inline shaders
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexIn {
            float4 position [[attribute(0)]];
            float2 texCoord [[attribute(1)]];
        };

        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };

        vertex VertexOut vertexShader(VertexIn in [[stage_in]]) {
            VertexOut out;
            out.position = in.position;
            out.texCoord = in.texCoord;
            return out;
        }

        fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                       texture2d<float> texture [[texture(0)]]) {
            constexpr sampler s(mag_filter::linear, min_filter::linear);
            return texture.sample(s, in.texCoord);
        }
        """

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            guard let vertexFunc = library.makeFunction(name: "vertexShader"),
                  let fragmentFunc = library.makeFunction(name: "fragmentShader") else {
                fatalError("Failed to create Metal shader functions")
            }

            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunc
            pipelineDescriptor.fragmentFunction = fragmentFunc
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

            // Vertex descriptor
            let vertexDescriptor = MTLVertexDescriptor()
            vertexDescriptor.attributes[0].format = .float4
            vertexDescriptor.attributes[0].offset = 0
            vertexDescriptor.attributes[0].bufferIndex = 0
            vertexDescriptor.attributes[1].format = .float2
            vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD4<Float>>.stride
            vertexDescriptor.attributes[1].bufferIndex = 0
            vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
            pipelineDescriptor.vertexDescriptor = vertexDescriptor

            self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create Metal pipeline state: \(error)")
        }

        super.init()

        // Set delegate
        metalView.delegate = self

        logger.info("MetalVideoRenderer initialized with device: \(device.name)")
    }

    deinit {
        cleanup()
    }

    // MARK: - Setup

    private var viewSize: CGSize {
        let drawable = metalView.drawableSize
        if drawable.width > 0, drawable.height > 0 { return drawable }
        return metalView.bounds.size
    }

    /// Rebuilds the fullscreen quad only when the frame about to be drawn
    /// comes from a video of another size, or the view size changed.
    private func prepareQuad(forFrameOf videoSize: CGSize, viewSize: CGSize) {
        guard let crop = WallpaperFrameCrop.rebuild(quadCrop, forFrameOf: videoSize, viewSize: viewSize) else { return }
        let rect = crop.textureRect
        let u0 = Float(rect.minX)
        let u1 = Float(rect.maxX)
        let v0 = Float(rect.minY)
        let v1 = Float(rect.maxY)
        // NDC y=-1 is the bottom of the screen; CV textures have v=0 at the top.
        let vertices: [Vertex] = [
            Vertex(position: SIMD4<Float>(-1, -1, 0, 1), texCoord: SIMD2<Float>(u0, v1)),
            Vertex(position: SIMD4<Float>( 1, -1, 0, 1), texCoord: SIMD2<Float>(u1, v1)),
            Vertex(position: SIMD4<Float>(-1,  1, 0, 1), texCoord: SIMD2<Float>(u0, v0)),
            Vertex(position: SIMD4<Float>( 1,  1, 0, 1), texCoord: SIMD2<Float>(u1, v0)),
        ]

        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Vertex>.stride,
            options: .storageModeShared
        )
        quadCrop = vertexBuffer == nil ? nil : crop
    }

    // MARK: - Video Loading

    func loadVideo(url: URL, trim: PlaybackTrim?) {
        loadTask?.cancel()
        loadGeneration &+= 1
        let generation = loadGeneration
        loadedURL = url
        loadedTrim = trim
        pendingTrimReload = nil
        trimReloadGeneration = nil
        playbackMonitor.beginLoad()
        guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path) else {
            failLoading(.missingFile)
            return
        }

        let trim = TrimmedVideoAsset.usableTrim(trim, for: url)
        let asset = TrimmedVideoAsset.sourceAsset(url: url, trim: trim)

        loadTask = Task { @MainActor [weak self] in
            do {
                let isPlayable = try await asset.load(.isPlayable)
                guard !Task.isCancelled, let self, generation == self.loadGeneration else { return }
                guard isPlayable else {
                    self.failLoading(.unplayable)
                    return
                }
                let playback = await TrimmedVideoAsset.playbackAsset(for: asset, trim: trim)
                // Size and HDR come from the source track: a composition
                // track does not carry the source's media characteristics.
                var videoSize = CGSize.zero
                var isHDR = false
                if let track = try await asset.loadTracks(withMediaType: .video).first {
                    let natural = try await track.load(.naturalSize)
                    let transform = try await track.load(.preferredTransform)
                    let displayed = CGRect(origin: .zero, size: natural).applying(transform)
                    videoSize = CGSize(width: abs(displayed.width), height: abs(displayed.height))
                    isHDR = await Self.isHDRSource(track)
                }

                // SDR sources keep the untouched path; only HDR needs conversion.
                let sdrComposition = isHDR
                    ? await Self.makeSDRVideoComposition(for: playback.asset, displayedSize: videoSize) : nil

                guard !Task.isCancelled, generation == self.loadGeneration else { return }
                self.setupPlayer(with: playback.asset, trim: playback.trim, videoComposition: sdrComposition,
                                 videoSize: videoSize, generation: generation)
            } catch {
                guard !Task.isCancelled, let self, generation == self.loadGeneration else { return }
                self.failLoading(.loadFailed)
            }
        }
    }

    /// Reloads the current video with an edited loop range, keeping its
    /// play/pause intent. While paused, the reload waits for the next resume:
    /// a paused reload would keep the previous frame, which can lie outside
    /// the new range, and report "Loading" until playback resumes.
    func applyTrim(_ trim: PlaybackTrim?) {
        guard let loadedURL else { return }
        // The full video plays and still would: removing a range that does not
        // apply keeps the current player instead of restarting it.
        if playerGeneration == loadGeneration, appliedTrim == nil,
           TrimmedVideoAsset.usableTrim(trim, for: loadedURL) == nil {
            loadedTrim = trim
            pendingTrimReload = nil
            return
        }
        guard wantsToPlay else {
            pendingTrimReload = trim == loadedTrim ? nil : PendingTrimReload(trim: trim)
            return
        }
        guard trim != loadedTrim else { return }
        loadTrimReload(url: loadedURL, trim: trim)
    }

    /// Loads a trim edit made while paused instead of resuming the old player
    /// outside the edited range. `setupPlayer` starts the new player and the
    /// display link; the retained frame stays on screen until then.
    private func startPendingTrimReload() -> Bool {
        guard let pending = pendingTrimReload, let loadedURL else { return false }
        loadTrimReload(url: loadedURL, trim: pending.trim)
        return true
    }

    private func loadTrimReload(url: URL, trim: PlaybackTrim?) {
        loadVideo(url: url, trim: trim)
        trimReloadGeneration = loadGeneration
    }

    /// While a trim edit loads, the current player still plays the previous
    /// range. Nothing may start it again before the edited player takes over.
    private var isWaitingForTrimReload: Bool {
        trimReloadGeneration == loadGeneration && playerGeneration != loadGeneration
    }

    /// A trim edit that finishes loading while paused presents its first frame,
    /// as AVPlayerLayer does, instead of keeping the previous range's frame
    /// and reporting Loading.
    private var needsPausedTrimFrame: Bool {
        !wantsToPlay && trimReloadGeneration == loadGeneration && playerGeneration == loadGeneration
            && frameGeneration != loadGeneration && !playbackMonitor.state.isFailed
    }

    private func failLoading(_ failure: RendererPlaybackFailure) {
        playbackMonitor.fail(failure)
    }

    /// Whether the track carries a PQ or HLG signal (HDR10, HLG, Dolby Vision).
    ///
    /// `.containsHDRVideo` is checked first; the format description's transfer
    /// function is a second opinion for files whose HDR flag is missing or
    /// incomplete. A failed property load counts as SDR so playback never
    /// depends on this check.
    @MainActor
    private static func isHDRSource(_ track: AVAssetTrack) async -> Bool {
        if let characteristics = try? await track.load(.mediaCharacteristics),
           characteristics.contains(.containsHDRVideo) {
            return true
        }
        guard let descriptions = try? await track.load(.formatDescriptions) else { return false }
        let hdrTransfers: [String] = [
            kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String,
            kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String
        ]
        return descriptions.contains { description in
            let transfer = CMFormatDescriptionGetExtension(
                description,
                extensionKey: kCMFormatDescriptionExtension_TransferFunction
            ) as? String
            return transfer.map(hdrTransfers.contains) ?? false
        }
    }

    /// Builds a composition that makes AVFoundation deliver BT.709 SDR frames,
    /// or returns `nil` (playing the source untouched) if it cannot be built.
    ///
    /// `AVPlayerItemVideoOutput` hands us raw 8-bit BGRA and the fragment shader
    /// samples it as-is, so there is no color management on this path. A PQ/HLG
    /// source would reach the screen as encoded HDR signal values and look
    /// washed out. Declaring BT.709 output on the composition makes
    /// AVFoundation tone-map the frames before they reach the video output.
    @MainActor
    private static func makeSDRVideoComposition(for asset: AVAsset, displayedSize: CGSize) async -> AVVideoComposition? {
        do {
            let base = try await AVVideoComposition.videoComposition(withPropertiesOf: asset)
            guard let composition = base.mutableCopy() as? AVMutableVideoComposition else { return nil }
            // For a trimmed composition the default render size is the track's
            // size before its transform, which would crop a rotated source.
            if asset is AVComposition, displayedSize.width > 0, displayedSize.height > 0 {
                composition.renderSize = displayedSize
            }
            composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
            composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
            composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
            logger.info("HDR source detected, tone-mapping to BT.709 SDR")
            return composition
        } catch {
            logger.error("HDR source left untouched, SDR composition failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Logs the color tags of the first frame decoded after each load. For an
    /// HDR source this should read ITU_R_709_2; a PQ/HLG value here means the
    /// tone-mapping is not taking effect.
    private func logFrameColorInfoOnce(_ pixelBuffer: CVPixelBuffer) {
        guard !hasLoggedFrameColorInfo else { return }
        hasLoggedFrameColorInfo = true
        let transfer = CVBufferCopyAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey, nil)
        let primaries = CVBufferCopyAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey, nil)
        logger.debug("First frame color tags: transfer=\(String(describing: transfer)) primaries=\(String(describing: primaries))")
    }

    private func setupPlayer(
        with asset: AVAsset,
        trim: PlaybackTrim?,
        videoComposition: AVVideoComposition? = nil,
        videoSize: CGSize,
        generation: UInt64
    ) {
        guard generation == loadGeneration else { return }

        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = 4.0
        playerItem.videoComposition = videoComposition

        // Single player + end-time seek. AVPlayerLooper copies the template
        // without the video output and, under CPU pressure, jumps a few
        // frames backward.
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: outputSettings)
        playerItem.add(output)

        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        newPlayer.preventsDisplaySleepDuringVideoPlayback = false
        newPlayer.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        newPlayer.isMuted = true
        newPlayer.actionAtItemEnd = .none

        let previousPlayer = player
        videoOutput = output
        playerVideoSize = videoSize
        player = newPlayer
        appliedTrim = trim
        playerGeneration = generation
        playbackMonitor.attach(newPlayer)
        lastPresentedSeconds = -1
        hasLoggedFrameColorInfo = false

        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self, weak newPlayer] _ in
            guard let self, let newPlayer, self.player === newPlayer else { return }
            self.lastPresentedSeconds = -1
            newPlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak newPlayer] finished in
                DispatchQueue.main.async {
                    guard finished, let self, let newPlayer,
                          self.player === newPlayer, self.wantsToPlay else { return }
                    newPlayer.play()
                }
            }
        }

        previousPlayer?.pause()
        previousPlayer?.replaceCurrentItem(with: nil)

        if wantsToPlay {
            pinOrStart()
            metalView.isPaused = true
            startDisplayLink()
        } else if needsPausedTrimFrame {
            startDisplayLink()
        }

        logger.info("Player setup complete")
    }

    // MARK: - Playback Control

    func applyPerformanceMode(_ mode: PerformanceManager.PerformanceMode) {
        performanceMode = mode
        // Manual draw() calls bypass MTKView's preferredFramesPerSecond.
        // Throttle before dispatching display-link work to the main queue.
        metalView.preferredFramesPerSecond = mode.maxFPS
        frameScheduler?.setMaximumFramesPerSecond(mode.maxFPS)
    }

    func play() {
        guard !playbackMonitor.state.isFailed else { return }
        wantsToPlay = true
        guard !startPendingTrimReload() else { return }
        pinOrStart()
        // Never use MTKView's internal timer: it auto-pauses when a windowed
        // app occludes the desktop overlay, and toggling it back on is a hitch.
        metalView.isPaused = true
        startDisplayLink()
        logger.debug("Playback started")
    }

    func pause() {
        wantsToPlay = false
        stopDisplayLink()
        player?.pause()
        if currentFrame != nil {
            metalView.draw()
        }
        metalView.isPaused = true
        if needsPausedTrimFrame {
            startDisplayLink()
        }
        logger.debug("Playback paused")
    }

    func stop() {
        cleanup()
    }

    // MARK: - Watchdog

    /// Playback clock in seconds for the watchdog. `nil` when no player is
    /// loaded or the time is not yet numeric (item not ready).
    var currentPlaybackTime: TimeInterval? {
        guard let time = player?.currentItem?.currentTime(), time.isNumeric else { return nil }
        return time.seconds
    }

    var currentPlaybackRate: Float {
        player?.rate ?? 0
    }

    func recoverPlayback() {
        guard !playbackMonitor.state.isFailed else { return }
        wantsToPlay = true
        guard !startPendingTrimReload() else { return }
        pinOrStart()
        metalView.isPaused = true
        startDisplayLink()
    }

    func maintainPlayback() {
        guard !playbackMonitor.state.isFailed else { return }
        guard wantsToPlay else { return }
        pinOrStart()
        metalView.isPaused = true
        startDisplayLink()
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        var link: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess,
              let link else { return }
        let scheduler = DisplayLinkFrameScheduler(maximumFramesPerSecond: performanceMode.maxFPS) { [weak self] in
            guard let self else { return }
            guard self.wantsToPlay || self.needsPausedTrimFrame else {
                // A paused trim reload has drawn its frame, or failed.
                if !self.wantsToPlay { self.stopDisplayLink() }
                return
            }
            self.metalView.draw()
        }
        // The retained block owns only the gate, not an unretained renderer
        // pointer. A callback racing with teardown cannot access freed state.
        guard CVDisplayLinkSetOutputHandler(link, { _, _, _, _, _ in
            scheduler.requestFrame()
            return kCVReturnSuccess
        }) == kCVReturnSuccess else { return }
        guard CVDisplayLinkStart(link) == kCVReturnSuccess else {
            scheduler.invalidate()
            return
        }
        frameScheduler = scheduler
        displayLink = link
    }

    private func stopDisplayLink() {
        frameScheduler?.invalidate()
        if let displayLink {
            CVDisplayLinkStop(displayLink)
            self.displayLink = nil
        }
        frameScheduler = nil
    }

    private func pinOrStart() {
        guard let player, !isWaitingForTrimReload else { return }
        if WallpaperPlaybackPolicy.shouldIssuePlay(currentRate: player.rate) {
            player.play()
        } else if WallpaperPlaybackPolicy.shouldCorrectRate(
            currentRate: player.rate, intendedToPlay: wantsToPlay
        ) {
            player.rate = 1
        }
    }

    // MARK: - Cleanup

    private func cleanup() {
        playbackMonitor.reset()
        loadGeneration &+= 1
        loadTask?.cancel()
        loadTask = nil
        wantsToPlay = false
        loadedURL = nil
        loadedTrim = nil
        pendingTrimReload = nil
        trimReloadGeneration = nil
        stopDisplayLink()
        metalView.isPaused = true

        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
        lastPresentedSeconds = -1
        player?.pause()
        player?.replaceCurrentItem(with: nil)

        videoOutput = nil
        player = nil
        appliedTrim = nil
        currentFrame = nil
        hasPresentedFrame = false

        if let cache = textureCache {
            CVMetalTextureCacheFlush(cache, 0)
        }
    }

    // MARK: - Frame Extraction

    private func extractCurrentFrame() -> VideoFrame? {
        guard let videoOutput = videoOutput,
              let currentItem = player?.currentItem else {
            return nil
        }

        let currentTime = currentItem.currentTime()
        guard currentTime.isNumeric else { return currentFrame }
        let seconds = currentTime.seconds
        if WallpaperAspectFill.shouldDiscardRewoundFrame(
            previousSeconds: lastPresentedSeconds, newSeconds: seconds
        ) {
            return currentFrame
        }
        guard videoOutput.hasNewPixelBuffer(forItemTime: currentTime) else {
            return currentFrame
        }

        guard let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) else {
            return currentFrame
        }

        lastPresentedSeconds = seconds
        logFrameColorInfoOnce(pixelBuffer)
        guard let frame = createTexture(from: pixelBuffer, videoSize: playerVideoSize) else { return nil }
        frameGeneration = playerGeneration
        return frame
    }

    private func createTexture(from pixelBuffer: CVPixelBuffer, videoSize: CGSize) -> VideoFrame? {
        guard let textureCache = textureCache else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )

        guard status == kCVReturnSuccess, let cvTexture = cvTexture else {
            return nil
        }

        guard let texture = CVMetalTextureGetTexture(cvTexture) else { return nil }
        return VideoFrame(texture: texture, videoSize: videoSize, backing: cvTexture, cache: textureCache)
    }
}

// MARK: - MTKViewDelegate

extension MetalVideoRenderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        guard let frame = currentFrame else { return }
        prepareQuad(forFrameOf: frame.videoSize, viewSize: size)
    }

    func draw(in view: MTKView) {
        renderLock.lock()
        defer { renderLock.unlock() }

        if wantsToPlay || needsPausedTrimFrame, let frame = extractCurrentFrame() {
            currentFrame = frame
        }

        // Never present an empty drawable — that is a black frame covering
        // the real wallpaper. Keep the last texture on screen across pause
        // and across a reload until the next frame arrives, with its own crop.
        guard let frame = currentFrame else { return }
        prepareQuad(forFrameOf: frame.videoSize, viewSize: viewSize)
        guard let vertexBuffer,
              let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        if !hasPresentedFrame {
            hasPresentedFrame = true
            DispatchQueue.main.async { [weak self] in
                self?.onBecameReady?()
            }
        }

        // Render fullscreen quad with video texture
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(frame.texture, index: 0)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        renderEncoder.endEncoding()
        // A replacement/stop can release currentFrame before the GPU finishes.
        // Each command buffer owns its frame, wrapper and cache until completion.
        commandBuffer.addCompletedHandler { [frame] _ in
            withExtendedLifetime(frame) {}
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
        if frameGeneration == loadGeneration, reportedFrameGeneration != loadGeneration {
            let generation = loadGeneration
            reportedFrameGeneration = generation
            DispatchQueue.main.async { [weak self] in
                guard let self, self.loadGeneration == generation else { return }
                self.playbackMonitor.framePresented()
            }
        }
    }
}
