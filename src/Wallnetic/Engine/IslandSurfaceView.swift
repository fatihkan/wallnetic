import AppKit
import Metal
import QuartzCore
import simd

/// How the island's surface is coloured.
struct IslandStyle: Equatable {
    /// The glow around the island, from the wallpaper's colours.
    var glow = SIMD3<Float>(0.45, 0.55, 1.0)
    /// 0 turns the glow off.
    var glowStrength: Float = 0.5
    /// Increase Contrast: a solid fill with an outline and no glow.
    var increasesContrast = false
}

/// Draws the Dynamic Island's liquid shape (#352): a signed-distance field of
/// rounded rectangles joined by a smooth union, in one small Metal pass.
///
/// It draws on demand only: when the shape, the style or the view's size
/// changes. While the island rests, no frame is drawn.
final class IslandSurfaceView: NSView {
    private let device = MTLCreateSystemDefaultDevice()
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var shape: IslandLayout?
    private var style = IslandStyle()
    private var drawnSize = CGSize.zero
    /// A frame is owed: the shape, the style or the size changed.
    private var isDirty = false

    /// Frames drawn so far. Tests and diagnostics read it to see that an
    /// idle island draws nothing.
    private(set) var drawCount = 0

    /// False when Metal is not usable. The caller then draws a plain shape.
    var isAvailable: Bool { pipeline != nil }

    /// The size of the frames being drawn, in pixels.
    var drawableSize: CGSize { drawnSize }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        // If a frame of another size is ever on screen, it hangs from the top
        // centre, as the shape does, at its own scale. It is never stretched
        // to the view: a stretched frame put the shape beside its content.
        // AppKit sets the layer's gravity from this; setting it on the layer
        // itself does not last.
        layerContentsPlacement = .top
        buildPipeline()
    }

    required init?(coder: NSCoder) { nil }

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.isOpaque = false
        layer.framebufferOnly = true
        // The frame lands in the same transaction as a change of the window's
        // size, so the shape never shows at the wrong size for a frame.
        layer.presentsWithTransaction = true
        return layer
    }

    /// Clicks belong to the controls in front of the surface.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Shows a shape. A frame is drawn only when something changed.
    func show(_ shape: IslandLayout, style: IslandStyle) {
        guard shape != self.shape || style != self.style else { return }
        self.shape = shape
        self.style = style
        invalidate()
    }

    // MARK: - One frame per change

    /// Asks for one frame. Nothing is drawn here: the frame is drawn once,
    /// when AppKit displays the view, with the shape and the size that hold
    /// then. Drawing at once and again after a resize presented two frames in
    /// one transaction; the second could be lost, and the first, drawn for
    /// the old size, stayed on screen.
    private func invalidate() {
        isDirty = true
        needsDisplay = true
        // A display pass normally comes first and leaves nothing to do here.
        DispatchQueue.main.async { [weak self] in self?.renderIfDirty() }
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        renderIfDirty()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { invalidate() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        invalidate()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        invalidate()
    }

    /// Draws the frame that is owed, if any, at the view's current size.
    func renderIfDirty() {
        guard isDirty, window != nil else { return }
        isDirty = false
        syncDrawable()
        guard !draw(), shape != nil, pipeline != nil, drawnSize.width >= 1 else { return }
        // No drawable was free. Try again shortly instead of leaving an old
        // frame on screen.
        isDirty = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.renderIfDirty() }
    }

    private func syncDrawable() {
        guard let metalLayer = layer as? CAMetalLayer, let window else { return }
        // A layer that joins a window late can keep a scale of zero and then
        // presents frames that show nothing.
        let scale = window.backingScaleFactor
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard size.width >= 1, size.height >= 1 else { return }
        if metalLayer.contentsScale != scale { metalLayer.contentsScale = scale }
        if metalLayer.drawableSize != size { metalLayer.drawableSize = size }
        drawnSize = size
    }

    // MARK: - Drawing

    /// Seven float4 values: the layout Metal gives the shader's struct.
    private struct Uniforms {
        var viewport: SIMD4<Float>
        var bar: SIMD4<Float>
        var card: SIMD4<Float>
        var radii: SIMD4<Float>
        var fill: SIMD4<Float>
        var glow: SIMD4<Float>
        var extra: SIMD4<Float>
    }

    /// Draws one frame. False when nothing could be drawn.
    @discardableResult
    private func draw() -> Bool {
        guard let shape, let pipeline, let queue, let metalLayer = layer as? CAMetalLayer,
              drawnSize.width >= 1, drawnSize.height >= 1, bounds.width > 0,
              let drawable = metalLayer.nextDrawable(),
              let commands = queue.makeCommandBuffer() else { return false }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return false }

        var uniforms = self.uniforms(for: shape)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commands.commit()
        commands.waitUntilScheduled()
        drawable.present()
        drawCount += 1
        return true
    }

    private func uniforms(for shape: IslandLayout) -> Uniforms {
        func rect(_ value: CGRect) -> SIMD4<Float> {
            SIMD4(Float(value.minX), Float(value.minY), Float(value.width), Float(value.height))
        }
        let scale = Float(drawnSize.width / max(bounds.width, 1))
        let contrast = style.increasesContrast
        let glowStrength: Float = contrast ? 0 : style.glowStrength
        let outline: Float = contrast ? 1 : 0
        // The glow ends two points inside the window, on every side.
        let glowReach = Float(IslandGeometry.margin) - 2
        let viewport = SIMD4<Float>(Float(bounds.width), Float(bounds.height), scale, 0)
        let radii = SIMD4<Float>(Float(shape.barRadius), Float(shape.cardRadius), 0, Float(shape.earRadius))
        // A notch is pure black, so the island is too.
        let fill = SIMD4<Float>(0, 0, 0, 1)
        let glow = SIMD4<Float>(style.glow.x, style.glow.y, style.glow.z, glowStrength)
        let extra = SIMD4<Float>(glowReach, outline, Float(shape.cardOpacity), Float(shape.glow))
        return Uniforms(viewport: viewport, bar: rect(shape.bar), card: rect(shape.card),
                        radii: radii, fill: fill, glow: glow, extra: extra)
    }

    private func buildPipeline() {
        guard let device else { return }
        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "islandVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "islandFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            queue = device.makeCommandQueue()
        } catch {
            Log.app.error("Island surface: Metal is not usable: \(error.localizedDescription)")
            pipeline = nil
        }
    }

    /// One triangle covers the view. The fragment shader measures each
    /// pixel's distance to the shape and colours it: black inside, a glow
    /// outside. The output is premultiplied, and the glow is an ordinary
    /// translucent colour that reaches zero before the view's edge.
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct IslandUniforms {
        float4 viewport;   // width, height in points; pixels per point; unused
        float4 bar;        // minX, minY, width, height
        float4 card;
        float4 radii;      // bar, card, unused, ear
        float4 fill;       // rgb, alpha
        float4 glow;       // rgb, strength
        float4 extra;      // glow reach, outline, card opacity, glow share
    };

    struct IslandVertex {
        float4 position [[position]];
        float2 uv;
    };

    vertex IslandVertex islandVertex(uint id [[vertex_id]]) {
        float2 corner = float2((id << 1) & 2, id & 2);
        IslandVertex out;
        out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
        out.uv = float2(corner.x, 1.0 - corner.y);
        return out;
    }

    // Distance to a rounded rectangle whose top edge is moved up by `lift`,
    // out of view, so the shape has a flat top at the screen's edge.
    static float roundedBox(float2 p, float4 rect, float radius, float lift) {
        float2 low = float2(rect.x, rect.y - lift);
        float2 high = float2(rect.x + rect.z, rect.y + rect.w);
        float2 extent = (high - low) * 0.5;
        float r = min(radius, min(extent.x, extent.y));
        float2 q = abs(p - (low + high) * 0.5) - extent + r;
        return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    }

    // A union whose seam is rounded over the distance k.
    static float smoothUnion(float a, float b, float k) {
        if (k <= 0.0) { return min(a, b); }
        float h = max(k - abs(a - b), 0.0) / k;
        return min(a, b) - h * h * k * 0.25;
    }

    // 1 at the shape's edge, 0 at `reach` and beyond, with no step.
    static float falloff(float distance, float reach) {
        float t = saturate(1.0 - max(distance, 0.0) / reach);
        return t * t;
    }

    fragment float4 islandFragment(IslandVertex in [[stage_in]], constant IslandUniforms &u [[buffer(0)]]) {
        float2 size = u.viewport.xy;
        float scale = max(u.viewport.z, 1.0);
        float2 p = float2((in.uv.x - 0.5) * size.x, in.uv.y * size.y);

        // The screen's top edge lies one point above the view. Joining it
        // gives the concave ears that flow into the edge. Bar and card are
        // joined plainly: the card always contains the bar.
        float edge = p.y + 1.0;
        float bar = smoothUnion(roundedBox(p, u.bar, u.radii.x, 64.0), edge, u.radii.w);
        float card = smoothUnion(roundedBox(p, u.card, u.radii.y, 64.0), edge, u.radii.w);
        float body = min(bar, card);

        float soft = 0.75 / scale;
        float fade = u.extra.z;
        float barCover = 1.0 - smoothstep(-soft, soft, bar);
        float bodyCover = 1.0 - smoothstep(-soft, soft, body);
        float cover = max(barCover, bodyCover * fade);

        // Light from the wallpaper, below the bar's own strip only, so the
        // menu bar beside the island stays clean. While the card fades, the
        // bar's light gives way to the card's.
        float reach = max(u.extra.x, 1.0);
        float below = smoothstep(u.bar.w - 1.0, u.bar.w + 5.0, p.y);
        float strength = u.glow.w * u.extra.w * below;
        float halo = mix(falloff(bar, reach), falloff(body, reach), fade) * strength * 0.55 * (1.0 - cover);
        float rim = mix(barCover * (1.0 - smoothstep(0.0, 1.5, -bar)),
                        bodyCover * (1.0 - smoothstep(0.0, 1.5, -body)), fade) * strength * 0.3;

        float3 colour = u.fill.rgb * u.fill.a * cover + u.glow.rgb * (halo + rim * cover);
        float alpha = u.fill.a * cover + halo;

        // Increase Contrast: a light outline just inside the edge.
        if (u.extra.y > 0.5) {
            float inside = fade >= 0.5 ? -body : -bar;
            float outline = cover * (1.0 - smoothstep(1.0, 1.0 + soft * 2.0, inside));
            colour = mix(colour, float3(0.92), outline);
            alpha = max(alpha, outline);
        }
        return float4(colour, min(alpha, 1.0));
    }
    """
}
