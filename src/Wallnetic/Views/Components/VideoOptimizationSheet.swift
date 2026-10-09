import SwiftUI
import AVKit

@MainActor
struct VideoOptimizationSheet: View {
    @StateObject private var model: VideoOptimizationModel
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var previewingOriginal = false

    init(wallpaper: Wallpaper) {
        _model = StateObject(wrappedValue: VideoOptimizationModel(source: wallpaper,
            optimizer: VideoOptimizer.shared, library: WallpaperManager.shared,
            refreshLibrary: { WallpaperManager.shared.loadWallpapers() }))
    }
    init(model: VideoOptimizationModel) { _model = StateObject(wrappedValue: model) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create optimized copy").font(.title2).fontWeight(.semibold)
                    Text(model.source.displayName).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
            }
            if model.isLoading { ProgressView("Checking video and codec support…") }
            if let result = model.result {
                resultView(result)
            } else {
                Picker("Preset", selection: $model.preset) {
                    ForEach(VideoOptimizationPreset.allCases) { Text($0.title).tag($0) }
                }.disabled(model.isWorking)
                Text(model.preset.detail).font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                if let reason = model.unavailableReason { Label(reason, systemImage: "exclamationmark.triangle").foregroundColor(.orange).font(.callout) }
                if let info = model.info {
                    Text("Source: \(Int(info.size.width)) × \(Int(info.size.height)) · \(String(format: "%.1f", info.frameRate)) fps · \(bytes(info.sourceBytes))")
                        .font(.caption).foregroundColor(.secondary)
                    if info.assumesSDR { Text("This video has incomplete color tags and will be treated as SDR Rec.709. Compare its colors before applying the copy.").font(.caption).foregroundColor(.orange) }
                }
                Text("Creates a separate, silent SDR video without enlarging the source. Lower frame rates reduce smoothness, not playback speed. HDR, transparency, wide-gamut and anamorphic videos are not supported. File size and energy savings vary.")
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                if model.isWorking {
                    ProgressView(value: model.progress)
                    Text(model.isCancelling ? "Cancelling and removing temporary files…" : (model.progress >= 0.95 ? "Checking the completed video…" : "Converting · \(Int(model.progress * 100))%"))
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            if let error = model.error { Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true) }
            if let message = model.message { Text(message).font(.caption).foregroundColor(.secondary) }
            Divider()
            HStack {
                if model.isWorking {
                    Button("Cancel conversion") { model.cancel() }.disabled(model.isCancelling)
                }
                Spacer()
                Button(model.result == nil ? "Close" : "Done") { dismiss() }.disabled(model.isWorking).keyboardShortcut(.cancelAction)
                if model.result == nil {
                    Button("Create copy") { model.start() }.disabled(!model.canStart).keyboardShortcut(.defaultAction)
                }
            }
        }.padding(24).frame(width: 540)
            .task { if model.info == nil && !model.isLoading { await model.load().value } }
            .interactiveDismissDisabled(model.isWorking)
            .onDisappear { model.cancel(); player?.pause(); player = nil }
    }

    private func resultView(_ result: OptimizedVideoResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Original \(bytes(result.sourceBytes))  →  Copy \(bytes(result.outputBytes))").font(.headline)
            Text("\(Int(result.size.width)) × \(Int(result.size.height)) · \(String(format: "%.1f", result.frameRate)) fps · \(String(format: "%.1f", result.duration)) seconds")
                .font(.caption).foregroundColor(.secondary)
            if result.outputBytes >= result.sourceBytes {
                Text("This copy is not smaller than the original. Compare both before choosing which to keep.").font(.caption).foregroundColor(.orange)
            }
            HStack {
                Button("Preview original") { preview(model.source.url, original: true) }
                Button("Preview copy") { preview(result.url, original: false) }
            }
            if let player {
                Text(previewingOriginal ? "Original" : "Optimized copy").font(.caption)
                VideoPlayer(player: player).frame(height: 160)
            }
            HStack {
                Button("Use original") { model.apply(model.source.url) }
                Button("Use optimized copy") { model.apply(result.url) }.buttonStyle(.borderedProminent)
            }
            Text("Both videos remain independent Library items. Use their context menu to switch back or delete either copy.")
                .font(.caption).foregroundColor(.secondary)
        }
    }
    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
    private func preview(_ url: URL, original: Bool) {
        player?.pause()
        let next = AVPlayer(url: url)
        next.isMuted = true
        player = next
        previewingOriginal = original
        next.play()
    }
}
