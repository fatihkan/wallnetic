import AVFoundation

/// Main-thread, event-driven status observation. Never issues playback commands.
/// Generations discard callbacks queued by an old item, retry, or cleanup.
final class RendererPlaybackMonitor {
    private(set) var state: RendererPlaybackState = .idle
    var onChange: (() -> Void)?
    private weak var player: AVPlayer?
    private var observations: [NSKeyValueObservation] = []
    private var generation = 0
    private var hasFrame = false

    func beginLoad() {
        detach()
        publish(.loading)
    }

    func attach(_ player: AVPlayer) {
        self.player = player
        let generation = generation
        let changed: () -> Void = { [weak self, weak player] in
            DispatchQueue.main.async {
                guard let self, let player, self.generation == generation,
                      self.player === player else { return }
                self.update()
            }
        }
        observations = [player.observe(\.timeControlStatus, options: [.initial, .new]) { _, _ in changed() }]
        if let item = player.currentItem {
            observations.append(item.observe(\.status, options: [.initial, .new]) { _, _ in changed() })
        }
    }

    func framePresented() {
        guard !hasFrame else { return }
        hasFrame = true
        update()
    }

    func fail(_ failure: RendererPlaybackFailure) {
        detach()
        publish(.failed(failure))
    }

    func reset() {
        detach()
        publish(.idle)
    }

    private func detach() {
        generation &+= 1
        observations.removeAll()
        player = nil
        hasFrame = false
    }

    private func update() {
        guard let player else { return }
        if player.currentItem?.status == .failed { publish(.failed(.loadFailed)); return }
        guard hasFrame else { publish(.loading); return }
        switch player.timeControlStatus {
        case .playing: publish(.playing)
        case .waitingToPlayAtSpecifiedRate: publish(.waiting)
        case .paused: publish(.paused)
        @unknown default: publish(.waiting)
        }
    }

    private func publish(_ next: RendererPlaybackState) {
        guard state != next else { return }
        state = next
        onChange?()
    }
}
