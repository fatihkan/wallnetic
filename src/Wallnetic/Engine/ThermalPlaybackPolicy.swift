import Foundation

/// Hysteresis for the optional thermal hold. Time is monotonic uptime, so
/// changing the wall clock cannot shorten the cooling interval.
struct ThermalPlaybackPolicy {
    static let seriousDelay: TimeInterval = 10
    static let recoveryDelay: TimeInterval = 60

    private(set) var isPaused = false
    private(set) var deadline: TimeInterval?
    private var pendingPause: Bool?

    mutating func update(enabled: Bool, state: ProcessInfo.ThermalState, at time: TimeInterval) {
        guard enabled else {
            isPaused = false
            cancelTransition()
            return
        }
        guard time.isFinite else { return }
        switch state {
        case .critical:
            isPaused = true
            cancelTransition()
        case .serious:
            transition(toPaused: true, after: Self.seriousDelay, at: time)
        case .nominal, .fair:
            transition(toPaused: false, after: Self.recoveryDelay, at: time)
        @unknown default:
            transition(toPaused: true, after: Self.seriousDelay, at: time)
        }
    }

    private mutating func transition(toPaused target: Bool, after delay: TimeInterval, at time: TimeInterval) {
        guard target != isPaused else { cancelTransition(); return }
        if pendingPause != target {
            pendingPause = target
            deadline = time + delay
        }
        if let deadline, time >= deadline {
            isPaused = target
            cancelTransition()
        }
    }

    private mutating func cancelTransition() {
        pendingPause = nil
        deadline = nil
    }
}
