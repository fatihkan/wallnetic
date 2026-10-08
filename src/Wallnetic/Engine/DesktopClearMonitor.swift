import Cocoa

/// Only a stable covered -> clear edge triggers replay. An initially clear
/// desktop, or a transient occlusion report, must not create a replay loop.
struct DesktopClearTransition {
    private var stable: Bool?
    private var candidate: Bool?
    private var samples = 0

    mutating func record(isClear: Bool) -> Bool {
        if candidate == isClear { samples += 1 } else { candidate = isClear; samples = 1 }
        guard samples >= 2 else { return false }
        let replay = stable == false && isClear
        stable = isClear
        samples = 2
        return replay
    }
}

/// Optional metadata-only check. No screen capture, window titles, accessibility
/// access, or private APIs. Stops completely when replay is disabled or paused.
final class DesktopClearMonitor {
    var onDesktopCleared: ((UInt32) -> Void)?
    private let queue = DispatchQueue(label: "com.wallnetic.desktop-clear", qos: .utility)
    private var timer: Timer?
    private var inFlight = false
    private var generation = 0
    private var transitions: [UInt32: DesktopClearTransition] = [:]

    func setEnabled(_ enabled: Bool) {
        if !enabled { stop(); return }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        sample()
    }

    func stop() {
        generation &+= 1
        timer?.invalidate()
        timer = nil
        inFlight = false
        transitions.removeAll()
    }

    private func sample() {
        guard !inFlight else { return }
        let screens = NSScreen.screens.compactMap { $0.displayID }
        let bounds = Dictionary(uniqueKeysWithValues: screens.map { ($0, CGDisplayBounds($0)) })
        let generation = generation
        inFlight = true
        queue.async { [weak self] in
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
            let clear = windows.map { windows in
                bounds.mapValues { screen in
                    !windows.contains { info in
                        guard (info[kCGWindowLayer as String] as? Int) == 0,
                              (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01 else { return false }
                        guard let data = info[kCGWindowBounds as String] as? [String: Any],
                              let rect = CGRect(dictionaryRepresentation: data as CFDictionary) else {
                            return true // Incomplete metadata must not trigger a replay.
                        }
                        return rect.intersects(screen)
                    }
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == generation, self.timer != nil else { return }
                self.inFlight = false
                guard let clear else { self.transitions.removeAll(); return }
                self.transitions = self.transitions.filter { clear[$0.key] != nil }
                for (id, isClear) in clear {
                    if self.transitions[id, default: DesktopClearTransition()].record(isClear: isClear) {
                        self.onDesktopCleared?(id)
                    }
                }
            }
        }
    }

    deinit { timer?.invalidate() }
}
