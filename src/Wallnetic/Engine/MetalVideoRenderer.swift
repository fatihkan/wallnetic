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
    private let draw: () -> Void

    init(draw: @escaping () -> Void) {
        self.draw = draw
    }

    func requestFrame() {
        lock.lock()
        guard isActive, !isPending else {
            lock.unlock()
            return
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
    private var playerLooper: AVPlayerLooper?
    private var queuePlayer: AVQueuePlayer?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var displayLink: CVDisplayLink?
    private var frameScheduler: DisplayLinkFrameScheduler?

    // MARK: - View

    let metalView: MTKView
    private var currentTexture: MTLTexture?
    private var vertexBuffer: MTLBuffer?
    private var videoSize: CGSize = .zero
    private var lastPresentedSeconds: Double = -1
    private var loopObserver: NSObjectProtocol?

    // MARK: - State

    /// User/controller wants playback. Distinct from "the player exists" —
    /// `play()` used to set this true while `player` was still nil, then
    /// `setupPlayer` never started it (`guard !isPlaying`), leaving a black
    /// MTKView forever.
    private var wantsToPlay = false
    private let renderLock = NSLock()
    private var loadGeneration: UInt64 = 0
    private var loadTask: Task<Void, Never>?
    private var currentItemObserver: NSKeyValueObservation?

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

        // Setup vertex buffer for fullscreen quad
        setupVertexBuffer()

        // Set delegate
        metalView.delegate = self

        logger.info("MetalVideoRenderer initialized with device: \(device.name)")
    }

    deinit {
        cleanup()
    }

    // MARK: - Setup

    private func setupVertexBuffer() {
        let viewSize: CGSize = {
            let drawable = metalView.drawableSize
            if drawable.width > 0, drawable.height > 0 { return drawable }
            return metalView.bounds.size
        }()
        let source = (videoSize.width > 0 && videoSize.height > 0) ? videoSize : viewSize
        let crop = WallpaperAspectFill.textureRect(videoSize: source, viewSize: viewSize)
        let u0 = Float(crop.minX)
        let u1 = Float(crop.maxX)
        let v0 = Float(crop.minY)
        let v1 = Float(crop.maxY)
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
    }

    // MARK: - Video Loading

    func loadVideo(url: URL) {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            logger.error("Video file does not exist: \(url.path)")
            return
        }

        loadTask?.cancel()
        loadGeneration &+= 1
        let generation = loadGeneration

        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false
        ])

        loadTask = Task { @MainActor [weak self] in
            do {
                let isPlayable = try await asset.load(.isPlayable)
                guard isPlayable else {
                    logger.error("Asset is not playable")
                    return
                }
                var videoSize = CGSize.zero
                if let track = try await asset.loadTracks(withMediaType: .video).first {
                    let natural = try await track.load(.naturalSize)
                    let transform = try await track.load(.preferredTransform)
                    let displayed = CGRect(origin: .zero, size: natural).applying(transform)
                    videoSize = CGSize(width: abs(displayed.width), height: abs(displayed.height))
                }

                guard !Task.isCancelled, let self, generation == self.loadGeneration else { return }
                self.videoSize = videoSize
                self.setupVertexBuffer()
                self.setupPlayer(with: asset, generation: generation)
            } catch {
                logger.error("Failed to load asset: \(error.localizedDescription)")
            }
        }
    }

    private func setupPlayer(with asset: AVURLAsset, generation: UInt64) {
        guard generation == loadGeneration else { return }

        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = 4.0

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
        player = newPlayer
        queuePlayer = nil
        playerLooper?.disableLooping()
        playerLooper = nil
        lastPresentedSeconds = -1

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
        }

        logger.info("Player setup complete")
    }

    // MARK: - Playback Control

    func play() {
        wantsToPlay = true
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
        if currentTexture != nil {
            metalView.draw()
        }
        metalView.isPaused = true
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
        wantsToPlay = true
        pinOrStart()
        metalView.isPaused = true
        startDisplayLink()
    }

    func maintainPlayback() {
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
        let scheduler = DisplayLinkFrameScheduler { [weak self] in
            guard let self, self.wantsToPlay else { return }
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
        guard let player else { return }
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
        loadGeneration &+= 1
        loadTask?.cancel()
        loadTask = nil
        wantsToPlay = false
        stopDisplayLink()
        metalView.isPaused = true

        currentItemObserver = nil
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
        lastPresentedSeconds = -1
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        playerLooper?.disableLooping()

        videoOutput = nil
        playerLooper = nil
        queuePlayer = nil
        player = nil
        currentTexture = nil
        hasPresentedFrame = false

        if let cache = textureCache {
            CVMetalTextureCacheFlush(cache, 0)
        }
    }

    // MARK: - Frame Extraction

    private func extractCurrentFrame() -> MTLTexture? {
        guard let videoOutput = videoOutput,
              let currentItem = player?.currentItem else {
            return nil
        }

        let currentTime = currentItem.currentTime()
        guard currentTime.isNumeric else { return currentTexture }
        let seconds = currentTime.seconds
        if WallpaperAspectFill.shouldDiscardRewoundFrame(
            previousSeconds: lastPresentedSeconds, newSeconds: seconds
        ) {
            return currentTexture
        }
        guard videoOutput.hasNewPixelBuffer(forItemTime: currentTime) else {
            return currentTexture
        }

        guard let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) else {
            return currentTexture
        }

        lastPresentedSeconds = seconds
        return createTexture(from: pixelBuffer)
    }

    private func createTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
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

        return CVMetalTextureGetTexture(cvTexture)
    }
}

// MARK: - MTKViewDelegate

extension MetalVideoRenderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        setupVertexBuffer()
    }

    func draw(in view: MTKView) {
        renderLock.lock()
        defer { renderLock.unlock() }

        if wantsToPlay, let texture = extractCurrentFrame() {
            currentTexture = texture
        }

        // Never present an empty drawable — that is a black frame covering
        // the real wallpaper. Keep the last texture on screen across pause
        // and across a reload until the next frame arrives.
        guard let texture = currentTexture,
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
        renderEncoder.setFragmentTexture(texture, index: 0)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
