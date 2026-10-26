import SwiftUI
import AVFoundation

/// Chooses the part of a Library video the wallpaper loops. The original file
/// is never changed; Save stores the range, Cancel leaves the stored one.
@MainActor
struct VideoTrimSheet: View {
    @StateObject private var model: VideoTrimModel
    @Environment(\.dismiss) private var dismiss

    init(wallpaper: Wallpaper) {
        _model = StateObject(wrappedValue: VideoTrimModel(wallpaper: wallpaper))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Trim loop").font(.title2).fontWeight(.semibold)
                Text(model.wallpaper.displayName).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
            }
            switch model.state {
            case .loading:
                ProgressView("Reading the video…")
            case .failed(let reason):
                Label(reason, systemImage: "exclamationmark.triangle").foregroundColor(.orange)
            case .ready:
                editor
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Button("Reset to Full Video") { model.resetToFullVideo() }
                    .disabled(model.state != .ready || model.isFullVideo)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { if model.save() { dismiss() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.state != .ready)
            }
        }
        .padding(20)
        .frame(width: 520)
        .task { await model.load() }
        .onDisappear { model.stopPreview() }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            LoopPreviewView(player: model.player)
                .frame(height: 200)
                .cornerRadius(8)
                .accessibilityLabel("Preview of the selected loop")
            Button(model.isPreviewPlaying ? "Pause Preview" : "Play Preview") { model.togglePreview() }
            timeRow("Start", time: model.start, set: model.setStart, step: model.stepStart)
            timeRow("End", time: model.end, set: model.setEnd, step: model.stepEnd)
            Text("Loop length \(VideoTrimModel.clockText(model.length)) of \(VideoTrimModel.clockText(model.duration - model.origin))")
                .font(.callout)
                .accessibilityLabel("Loop length \(VideoTrimModel.spokenText(model.length)), of \(VideoTrimModel.spokenText(model.duration - model.origin))")
            Text(model.hasExactFrames
                 ? "The original file is not changed. Each step moves to the next or previous frame; a loop is at least one second long."
                 : "The original file is not changed. Steps use the video's shortest frame interval; a loop is at least one second long.")
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            if let note = model.note {
                Label(note, systemImage: "info.circle").font(.caption).foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func timeRow(_ title: String, time: CMTime, set: @escaping (CMTime) -> Void,
                         step: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title).frame(width: 40, alignment: .leading).accessibilityHidden(true)
            Slider(value: Binding(get: { time.seconds },
                                  set: { set(CMTime(seconds: $0, preferredTimescale: 6_000)) }),
                   in: model.origin.seconds...max(model.origin.seconds + 0.001, model.duration.seconds))
                .accessibilityLabel(title)
                .accessibilityValue(VideoTrimModel.spokenText(time))
            Text(VideoTrimModel.clockText(time))
                .font(.system(.body, design: .monospaced))
                .frame(width: 80, alignment: .trailing)
                .accessibilityHidden(true)
            Stepper("\(title), one frame", onIncrement: { step(1) }, onDecrement: { step(-1) })
                .labelsHidden()
                .accessibilityLabel("\(title), one frame")
                .accessibilityValue(VideoTrimModel.spokenText(time))
        }
    }
}

/// Plays a player without controls, so the preview cannot be scrubbed
/// outside the selection.
private struct LoopPreviewView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> LoopPreviewHostView {
        let view = LoopPreviewHostView(frame: .zero)
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ nsView: LoopPreviewHostView, context: Context) {
        nsView.playerLayer.player = player
    }
}

/// Hosts the player layer as a sublayer, as the desktop renderer does, so
/// AppKit cannot change its gravity.
private final class LoopPreviewHostView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}
