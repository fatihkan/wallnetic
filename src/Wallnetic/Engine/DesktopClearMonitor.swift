import Cocoa

/// Only a stable covered -> clear edge triggers replay. An initially clear
/// desktop, or a transient occlusion report, must not create a replay loop.
/// Unknown samples break continuity and require a fresh covered -> clear edge.
struct DesktopClearTransition {
    private var stable: Bool?
    private var candidate: Bool?
    private var samples = 0

    mutating func record(isClear: Bool?) -> Bool {
        guard let isClear else {
            self = Self()
            return false
        }
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
                bounds.mapValues { Self.isDesktopClear(on: $0, windows: windows) }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == generation, self.timer != nil else { return }
                self.inFlight = false
                guard let clear else { self.transitions.removeAll(); return }
                self.transitions = self.transitions.filter { clear.keys.contains($0.key) }
                for (id, isClear) in clear {
                    if self.transitions[id, default: DesktopClearTransition()].record(isClear: isClear) {
                        self.onDesktopCleared?(id)
                    }
                }
            }
        }
    }

    /// nil means the metadata cannot establish visibility. A confirmed regular
    /// window proves coverage; reporting clear requires every window to be known.
    static func isDesktopClear(on screen: CGRect, windows: [[String: Any]]) -> Bool? {
        guard hasValidGeometry(screen), screen.width > 0, screen.height > 0 else { return nil }
        var hasUnknownWindow = false
        for info in windows {
            guard let rawLayer = finiteNumber(info[kCGWindowLayer as String]),
                  let layer = Int32(exactly: rawLayer) else {
                hasUnknownWindow = true
                continue
            }
            guard layer == 0 else { continue }
            guard let alpha = finiteNumber(info[kCGWindowAlpha as String]), (0...1).contains(alpha) else {
                hasUnknownWindow = true
                continue
            }
            guard alpha > 0.01 else { continue }
            guard let data = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: data as CFDictionary), hasValidGeometry(rect) else {
                hasUnknownWindow = true
                continue
            }
            guard rect.width > 0, rect.height > 0 else { continue }
            if rect.intersects(screen) { return false }
        }
        return hasUnknownWindow ? nil : true
    }

    private static func finiteNumber(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    private static func hasValidGeometry(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, rect.maxX, rect.maxY].allSatisfy(\.isFinite)
            && rect.size.width >= 0 && rect.size.height >= 0
    }

    deinit { timer?.invalidate() }
}
