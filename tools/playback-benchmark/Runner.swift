import AppKit
import AVFoundation
import CryptoKit
import IOKit.ps
import MetalKit

private let missing = NSNull()
private struct BenchmarkError: Error, CustomStringConvertible { let description: String }

/// The "clock" run condition (#311): static text composited above the video,
/// as a sibling of the renderer view so wallpaper effects could not reach it.
/// It never changes during a run. This approximates the cost of drawing a layer
/// over the video; it does not run the app's clock code.
private func clockOverlayContainer(_ rendererView: NSView, size: NSSize, scale: CGFloat) -> NSView {
    let container = NSView(frame: NSRect(origin: .zero, size: size))
    container.wantsLayer = true
    rendererView.frame = container.bounds
    rendererView.autoresizingMask = [.width, .height]
    container.addSubview(rendererView)
    let text = CATextLayer()
    text.string = "10:09"
    text.font = NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .semibold)
    text.fontSize = max(12, min(size.width, size.height) / 5)
    text.foregroundColor = NSColor.white.cgColor
    text.alignmentMode = .center
    text.contentsScale = scale
    text.frame = CGRect(x: 0, y: (size.height - text.fontSize * 1.3) / 2, width: size.width, height: text.fontSize * 1.3)
    text.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
    container.layer?.addSublayer(text)
    return container
}

// These are delegate invocations, NOT presented/unique frames. No GPU readback.
private final class DrawCounter: NSObject, MTKViewDelegate {
    let renderer: MetalVideoRenderer
    var times: [Double] = []
    var recording = false
    init(_ renderer: MetalVideoRenderer) { self.renderer = renderer }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderer.mtkView(view, drawableSizeWillChange: size)
    }
    func draw(in view: MTKView) {
        if recording { times.append(ProcessInfo.processInfo.systemUptime) }
        renderer.draw(in: view)
    }
}

@main struct Runner {
    static func systemValue(_ key: String) -> String {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &bytes, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: bytes)
    }

    static func power() -> String {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return "unknown" }
        return type as String
    }

    static func metrics() throws -> BenchmarkMetrics {
        var result = BenchmarkMetrics()
        guard benchmark_metrics(&result) == 0 else { throw BenchmarkError(description: "getrusage failed") }
        return result
    }

    static func output(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }

    static func media(_ url: URL) async throws -> [String: Any] {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) > 0, (values.fileSize ?? 0) <= 512 * 1024 * 1024 else {
            throw BenchmarkError(description: "Media must be a nonempty regular file of at most 512 MiB")
        }
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable), let track = try await asset.loadTracks(withMediaType: .video).first,
              let description = try await track.load(.formatDescriptions).first else {
            throw BenchmarkError(description: "Playable video track unavailable")
        }
        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
        let subtype = CMFormatDescriptionGetMediaSubType(description)
        let code = (0..<4).map { UInt8((subtype >> (24 - $0 * 8)) & 255) }
        return ["sha256": SHA256.hash(data: try Data(contentsOf: url, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined(),
            "bytes": values.fileSize ?? 0, "codec_fourcc": String(bytes: code, encoding: .ascii) ?? "unknown",
            "width": Int(dimensions.width), "height": Int(dimensions.height),
            "fps": try await track.load(.nominalFrameRate), "duration_seconds": try await asset.load(.duration).seconds]
    }

    @MainActor static func screens() -> [[String: Any]] {
        NSScreen.screens.enumerated().map { index, screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let mode = CGDisplayCopyDisplayMode(id)
            return ["index": index, "id": id, "name": screen.localizedName,
                "mirrors_display_id": CGDisplayMirrorsDisplay(id), "built_in": CGDisplayIsBuiltin(id) != 0,
                "frame_points": [screen.frame.origin.x, screen.frame.origin.y, screen.frame.width, screen.frame.height],
                "scale": screen.backingScaleFactor, "pixel_width": mode?.pixelWidth ?? 0,
                "pixel_height": mode?.pixelHeight ?? 0, "refresh_hz": mode?.refreshRate ?? 0]
        }
    }

    @MainActor static func run() async throws {
        let args = CommandLine.arguments
        if args.count == 3, args[1] == "--inspect" {
            try await output(media(URL(fileURLWithPath: args[2])))
            return
        }
        // CLI validation is repeated here so direct invocation also fails safely.
        guard args.count == 10, ["metal", "avplayer"].contains(args[1]), ["none", "clock"].contains(args[9]),
              let mode = ["quality": PerformanceManager.PerformanceMode.quality, "balanced": .balanced, "battery": .battery][args[2]],
              let warmup = Double(args[4]), warmup.isFinite, (0...300).contains(warmup),
              let duration = Double(args[5]), duration.isFinite, (1...600).contains(duration),
              let width = Double(args[7]), width.isFinite, (64...8192).contains(width),
              let height = Double(args[8]), height.isFinite, (64...8192).contains(height) else {
            throw BenchmarkError(description: "Use benchmark.py run for validated arguments")
        }
        let indices = args[6].split(separator: ",").compactMap { Int($0) }
        guard !indices.isEmpty, indices.count == args[6].split(separator: ",", omittingEmptySubsequences: false).count,
              Set(indices).count == indices.count, indices.allSatisfy({ NSScreen.screens.indices.contains($0) }) else {
            throw BenchmarkError(description: "Choose distinct connected screen indices")
        }
        guard args[1] != "metal" || MetalVideoRenderer.isSupported else {
            throw BenchmarkError(description: "Metal unavailable; engine substitution is not allowed")
        }
        let url = URL(fileURLWithPath: args[3])
        let fixture = try await media(url)
        let connected = screens()
        // Do not suppress display/system sleep or mutate Wallnetic preferences.
        let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Isolated renderer benchmark")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        var renderers: [WallpaperRenderer] = []
        var windows: [NSWindow] = []
        var counters: [DrawCounter?] = []
        defer {
            for renderer in renderers { renderer.stop() }
            for window in windows { window.contentView = nil; window.close() }
        }
        for index in indices {
            let screen = NSScreen.screens[index]
            guard width <= screen.visibleFrame.width, height <= screen.visibleFrame.height else {
                throw BenchmarkError(description: "Requested window does not fit selected screen; reduce --width/--height")
            }
            let renderer: WallpaperRenderer = args[1] == "metal" ? MetalVideoRenderer() : VideoRenderer()
            let counter = (renderer as? MetalVideoRenderer).map(DrawCounter.init)
            if let metal = renderer as? MetalVideoRenderer { metal.metalView.delegate = counter }
            let frame = NSRect(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.midY - height / 2,
                width: width, height: height)
            let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = "Wallnetic isolated renderer benchmark"
            window.contentView = args[9] == "clock"
                ? clockOverlayContainer(renderer.rendererView, size: frame.size, scale: screen.backingScaleFactor)
                : renderer.rendererView
            window.orderFrontRegardless()
            windows.append(window); renderers.append(renderer); counters.append(counter)
            renderer.applyPerformanceMode(mode)
            renderer.loadVideo(url: url)
            renderer.play()
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        while !renderers.allSatisfy(\.hasPresentedFrame) {
            guard ProcessInfo.processInfo.systemUptime < deadline, !renderers.contains(where: { $0.playbackMonitor.state.isFailed }) else {
                throw BenchmarkError(description: "Renderer failed to become ready within 30 seconds")
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try await Task.sleep(nanoseconds: UInt64(warmup * 1_000_000_000))
        let state: () -> [String: Any] = {
            ["power_source": power(), "low_power_mode": ProcessInfo.processInfo.isLowPowerModeEnabled,
             "thermal_state": ProcessInfo.processInfo.thermalState.rawValue]
        }
        let initialState = state()
        var invalid = Set<String>()
        if initialState["power_source"] as? String == "unknown" { invalid.insert("unknown power source") }
        if ProcessInfo.processInfo.thermalState != .nominal { invalid.insert("non-nominal thermal state") }
        let startUsage = try metrics()
        let start = ProcessInfo.processInfo.systemUptime
        let date = Date()
        counters.forEach { $0?.recording = true }
        var samples: [[String: Any]] = []
        var footprints: [UInt64] = []
        var lastTick = start
        repeat {
            try await Task.sleep(nanoseconds: UInt64(min(1, max(0.001, duration - (ProcessInfo.processInfo.systemUptime - start))) * 1_000_000_000))
            let now = ProcessInfo.processInfo.systemUptime
            let usage = try metrics()
            let currentState = state()
            if !NSDictionary(dictionary: initialState).isEqual(to: currentState) { invalid.insert("power or thermal state changed") }
            if now - lastTick > 2.5 { invalid.insert("sampling interrupted") }
            lastTick = now
            let visible = windows.map { $0.isVisible && $0.occlusionState.contains(.visible) }
            if visible.contains(false) { invalid.insert("window reported occluded or hidden") }
            if renderers.contains(where: { $0.playbackMonitor.state.isFailed || abs($0.currentPlaybackRate - 1) > 0.02 }) {
                invalid.insert("playback failed or rate deviated")
            }
            if usage.process_usage_available != 0 { footprints.append(usage.footprint_bytes) }
            samples.append(["elapsed_seconds": now - start, "cpu_seconds": usage.cpu_seconds - startUsage.cpu_seconds,
                "footprint_bytes": usage.process_usage_available != 0 ? usage.footprint_bytes as Any : missing,
                "resident_bytes": usage.process_usage_available != 0 ? usage.resident_bytes as Any : missing,
                "power": currentState, "windows_visible": visible,
                "playback_seconds": renderers.map { $0.currentPlaybackTime as Any? ?? missing },
                "player_rates": renderers.map(\.currentPlaybackRate)])
        } while ProcessInfo.processInfo.systemUptime - start < duration
        counters.forEach { $0?.recording = false }
        let end = ProcessInfo.processInfo.systemUptime
        let endUsage = try metrics()
        let elapsed = end - start
        if abs(Date().timeIntervalSince(date) - elapsed) > 2 { invalid.insert("wall and monotonic clocks diverged") }
        if !NSArray(array: connected).isEqual(to: screens()) { invalid.insert("display configuration changed") }
        if footprints.count != samples.count { invalid.insert("process memory metrics unavailable") }
        let drawStats: [Any] = counters.map { counter in
            guard let counter else { return missing }
            let gaps = zip(counter.times.dropFirst(), counter.times).map { ($0 - $1) * 1000 }.sorted()
            return ["calls": counter.times.count, "calls_per_second": Double(counter.times.count) / elapsed,
                "interval_p95_ms": gaps.isEmpty ? missing as Any : gaps[min(gaps.count - 1, Int(ceil(Double(gaps.count) * 0.95)) - 1)],
                "interval_max_ms": gaps.last as Any? ?? missing]
        }
        let usageAvailable = startUsage.process_usage_available != 0 && endUsage.process_usage_available != 0
            && endUsage.package_idle_wakeups >= startUsage.package_idle_wakeups
            && endUsage.interrupt_wakeups >= startUsage.interrupt_wakeups
        try output(["schema_version": 1, "scope": "isolated_renderer_host", "started_at": ISO8601DateFormatter().string(from: date),
            "hardware": ["model": systemValue("hw.model"), "cpu": systemValue("machdep.cpu.brand_string"),
                "gpu_names": MTLCopyAllDevices().map(\.name),
                "logical_cpus": ProcessInfo.processInfo.activeProcessorCount, "memory_bytes": ProcessInfo.processInfo.physicalMemory],
            "os": ["version": ProcessInfo.processInfo.operatingSystemVersionString, "build": systemValue("kern.osversion")],
            "engine": args[1], "profile": args[2], "overlay": args[9], "warmup_seconds": warmup, "requested_seconds": duration,
            "elapsed_seconds": elapsed, "window_points": [width, height], "screen_indices": indices, "connected_screens": connected,
            "fixture": fixture, "power_start": initialState, "power_end": state(), "samples": samples,
            "invalid_reasons": invalid.sorted(), "eligible_for_baseline": invalid.isEmpty && warmup >= 30 && duration >= 60,
            "metrics": ["cpu_percent_one_core": (endUsage.cpu_seconds - startUsage.cpu_seconds) / elapsed * 100,
                "footprint_peak_sampled_bytes": footprints.max() as Any? ?? missing,
                "footprint_mean_sampled_bytes": footprints.isEmpty ? missing as Any : footprints.reduce(0.0) { $0 + Double($1) } / Double(footprints.count),
                "package_idle_wakeups_per_second": usageAvailable ? Double(endUsage.package_idle_wakeups - startUsage.package_idle_wakeups) / elapsed as Any : missing,
                "interrupt_wakeups_per_second": usageAvailable ? Double(endUsage.interrupt_wakeups - startUsage.interrupt_wakeups) / elapsed as Any : missing,
                "metal_draw_delegate": drawStats, "presented_frame_pacing": missing, "gpu_utilization": missing,
                "energy_impact": missing, "auxiliary_process_cost": missing, "black_frame_check": "not_measured", "switching_check": "not_measured"],
            "activity_policy": "userInitiatedAllowingIdleSystemSleep", "sampling_interval_seconds": 1])
    }

    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                try await run()
                app.terminate(nil)
            } catch {
                FileHandle.standardError.write(Data("Benchmark error: \(error)\n".utf8))
                exit(1)
            }
        }
        // Service AppKit events (including occlusion) during async measurements.
        app.run()
    }
}
