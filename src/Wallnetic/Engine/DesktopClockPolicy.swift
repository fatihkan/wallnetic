import Foundation
import CoreGraphics

/// Pure rules for the desktop clock (#311). The clock reads presented-frame
/// flags and pause reasons as values and never changes playback.
enum DesktopClockPolicy {
    /// Reasons under which nothing on any display can be seen: the display
    /// sleeps, the session is locked or switched away, or a screen saver runs.
    /// Every clock hides and the scheduler stops.
    static let sessionHidingReasons: Set<PlaybackPauseReason> = [.sleeping, .sessionInactive, .screenSaver]

    /// Whether a display shows its clock. A paused wallpaper keeps its still
    /// frame on screen, so the clock keeps updating over it for manual,
    /// timer, Calm, thermal, battery, Low Power and fullscreen pauses.
    /// Hiding it then would make it vanish whenever an unrelated feature
    /// pauses playback; freezing it would show a wrong time.
    static func isVisible(enabled: Bool, hasPresentedFrame: Bool, reasons: [PlaybackPauseReason]) -> Bool {
        enabled && hasPresentedFrame && sessionHidingReasons.isDisjoint(with: reasons)
    }

    /// The first minute boundary strictly after `date`. Minutes keep their
    /// length across DST changes, which move hours, not minutes.
    static func nextMinuteBoundary(after date: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        let start = calendar.dateInterval(of: .minute, for: date)?.start ?? date
        return start.addingTimeInterval(60)
    }
}

/// Where the clock sits inside a display's visible area (not under the menu
/// bar or the Dock), in the wallpaper window's coordinates (origin bottom left).
enum DesktopClockLayout {
    /// Space from the visible area's edges, as a share of its height.
    static let marginFraction: CGFloat = 0.04

    static func origin(for size: CGSize, in visible: CGRect, position: DesktopClockSettings.Position) -> CGPoint {
        let margin = (visible.height * marginFraction).rounded()
        let x: CGFloat
        switch position {
        case .topLeading, .bottomLeading: x = visible.minX + margin
        case .topCenter, .center, .bottomCenter: x = visible.midX - size.width / 2
        case .bottomTrailing: x = visible.maxX - margin - size.width
        }
        let y: CGFloat
        switch position {
        case .topLeading, .topCenter: y = visible.maxY - margin - size.height
        case .center: y = visible.midY - size.height / 2
        case .bottomLeading, .bottomCenter, .bottomTrailing: y = visible.minY + margin
        }
        // A clock larger than the area stays anchored to its top-left corner.
        let clampedX = max(visible.minX, min(x, visible.maxX - size.width))
        let clampedY = min(visible.maxY - size.height, max(y, visible.minY))
        return CGPoint(x: clampedX.rounded(), y: clampedY.rounded())
    }

    /// A screen's visible frame in its own window's coordinates.
    static func visibleRect(screenFrame: CGRect, visibleFrame: CGRect) -> CGRect {
        visibleFrame.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
    }
}
