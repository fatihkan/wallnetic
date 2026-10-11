import Foundation
import Combine

enum PlaybackHold: Hashable {
    case calm, thermal

    var pauseReason: PlaybackPauseReason { self == .calm ? .calm : .thermal }
}

/// Main-thread settings and thermal observation. Calm Mode is session-only;
/// only the thermal opt-in is persisted. Neither setting owns playback intent.
final class CalmPlaybackSettings: ObservableObject {
    static let shared = CalmPlaybackSettings()
    static let thermalEnabledKey = "playback.thermalAwareEnabled"

    struct State: Equatable {
        var isCalmEnabled = false
        var isThermalEnabled = false
        var isThermallyPaused = false

        var holds: Set<PlaybackHold> {
            var result: Set<PlaybackHold> = []
            if isCalmEnabled { result.insert(.calm) }
            if isThermallyPaused { result.insert(.thermal) }
            return result
        }
    }

    @Published private(set) var state = State()
    private let defaults: UserDefaults
    private let center: NotificationCenter
    private let thermalState: () -> ProcessInfo.ThermalState
    private let now: () -> TimeInterval
    private var policy = ThermalPlaybackPolicy()
    private var observer: NSObjectProtocol?
    private var timer: Timer?

    init(defaults: UserDefaults = .standard, center: NotificationCenter = .default,
         thermalState: @escaping () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState },
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.defaults = defaults
        self.center = center
        self.thermalState = thermalState
        self.now = now
        state.isThermalEnabled = defaults.bool(forKey: Self.thermalEnabledKey)
        // Apple requires reading thermalState before registering for changes.
        refreshThermalState()
        observer = center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                                      object: nil, queue: .main) { [weak self] _ in
            self?.refreshThermalState()
        }
        // Close the read/register gap without restarting a pending deadline.
        refreshThermalState()
    }

    deinit {
        timer?.invalidate()
        if let observer { center.removeObserver(observer) }
    }

    func setCalmEnabled(_ enabled: Bool) {
        guard state.isCalmEnabled != enabled else { return }
        var next = state
        next.isCalmEnabled = enabled
        state = next
    }

    func toggleCalmMode() { setCalmEnabled(!state.isCalmEnabled) }

    func setThermalEnabled(_ enabled: Bool) {
        guard state.isThermalEnabled != enabled else { return }
        defaults.set(enabled, forKey: Self.thermalEnabledKey)
        refreshThermalState(enabled: enabled)
    }

    func refreshThermalState() { refreshThermalState(enabled: state.isThermalEnabled) }

    private func refreshThermalState(enabled: Bool) {
        let time = now()
        policy.update(enabled: enabled, state: thermalState(), at: time)
        var next = state
        next.isThermalEnabled = enabled
        next.isThermallyPaused = policy.isPaused
        if next != state { state = next }

        timer?.invalidate()
        timer = nil
        if let deadline = policy.deadline {
            let timer = Timer(timeInterval: max(0.01, deadline - time), repeats: false) { [weak self] _ in
                self?.refreshThermalState()
            }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }
}
