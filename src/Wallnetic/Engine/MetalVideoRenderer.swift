import Cocoa
import AVFoundation
import Metal
import MetalKit
import CoreVideo
import os.log

private let logger = Logger(subsystem: "com.wallnetic.app", category: "MetalVideoRenderer")

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

    // MARK: - View

    let metalView: MTKView
    private var currentTexture: MTLTexture?
    private var vertexBuffer: MTLBuffer?

    // MARK: - State

    private var isPlaying = false
    private let renderLock = NSLock()

    // MARK: - Vertex Data

    private struct Vertex {
        var position: SIMD4<Float>
        var texCoord: SIMD2<Float>
    }

    // MARK: - Initialization

    override init() {
        // Create Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
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
        // Fullscreen quad vertices (position + texCoord)
        let vertices: [Vertex] = [
            Vertex(position: SIMD4<Float>(-1, -1, 0, 1), texCoord: SIMD2<Float>(0, 1)),
            Vertex(position: SIMD4<Float>( 1, -1, 0, 1), texCoord: SIMD2<Float>(1, 1)),
            Vertex(position: SIMD4<Float>(-1,  1, 0, 1), texCoord: SIMD2<Float>(0, 0)),
            Vertex(position: SIMD4<Float>( 1,  1, 0, 1), texCoord: SIMD2<Float>(1, 0)),
        ]

        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Vertex>.stride,
            options: .storageModeShared
        )
    }

    // MARK: - Video Loading

    func loadVideo(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.error("Video file does not exist: \(url.path)")
            return
        }

        cleanup()

        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false
        ])

        Task { @MainActor in
            do {
                let isPlayable = try await asset.load(.isPlayable)
                guard isPlayable else {
                    logger.error("Asset is not playable")
                    return
                }
                setupPlayer(with: asset)
            } catch {
                logger.error("Failed to load asset: \(error.localizedDescription)")
            }
        }
    }

    private func setupPlayer(with asset: AVURLAsset) {
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = 2.0

        // Disable audio tracks
        for track in playerItem.asset.tracks(withMediaType: .audio) {
            if let assetTrack = playerItem.tracks.first(where: { $0.assetTrack?.trackID == track.trackID }) {
                assetTrack.isEnabled = false
            }
        }

        // Setup video output for Metal texture generation
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: outputSettings)
        playerItem.add(videoOutput!)

        // Setup looping player
        queuePlayer = AVQueuePlayer()
        queuePlayer?.automaticallyWaitsToMinimizeStalling = false
        queuePlayer?.preventsDisplaySleepDuringVideoPlayback = false
        queuePlayer?.isMuted = true

        playerLooper = AVPlayerLooper(player: queuePlayer!, templateItem: playerItem)
        player = queuePlayer

        logger.info("Player setup complete")
    }

    // MARK: - Playback Control

    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        player?.play()
        metalView.isPaused = false
        logger.debug("Playback started")
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        player?.pause()
        metalView.isPaused = true
        logger.debug("Playback paused")
    }

    func stop() {
        cleanup()
    }

    // MARK: - Cleanup

    private func cleanup() {
        isPlaying = false
        metalView.isPaused = true

        player?.pause()
        player?.replaceCurrentItem(with: nil)
        playerLooper?.disableLooping()

        videoOutput = nil
        playerLooper = nil
        queuePlayer = nil
        player = nil
        currentTexture = nil

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
        guard videoOutput.hasNewPixelBuffer(forItemTime: currentTime) else {
            return currentTexture // Return cached texture if no new frame
        }

        guard let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) else {
            return currentTexture
        }

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
        // Handle size changes if needed
    }

    func draw(in view: MTKView) {
        renderLock.lock()
        defer { renderLock.unlock() }

        guard isPlaying,
              let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        // Get current video frame texture
        if let texture = extractCurrentFrame() {
            currentTexture = texture
        }

        guard let texture = currentTexture else {
            renderEncoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
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

