import AppKit

extension NSScreen {
    /// Stable identifier for the underlying display — survives most
    /// topology changes (sleep/wake, resolution toggle, hot-plug) where the
    /// `NSScreen` *object* identity does not. Prefer this over the screen
    /// object or `localizedName` as a dictionary key: object identity is
    /// recreated on reconfiguration (stale keys → missed lookups) and
    /// `localizedName` collides across identical displays.
    ///
    /// Returns nil for the rare screen with no `NSScreenNumber` device entry.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
