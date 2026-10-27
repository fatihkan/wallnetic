import Foundation

/// Time and date text for the desktop clock, from the user's region and
/// 12/24-hour setting. Formatters are made per call, at most once per update
/// of all displays, so a changed region, time zone or clock setting applies at
/// the next update.
enum DesktopClockFormat {
    /// The short time style follows the 12/24-hour setting.
    static func time(_ date: Date, locale: Locale = .autoupdatingCurrent,
                     timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Weekday, day and month in the region's own order, e.g. "Monday, 26 October".
    static func date(_ date: Date, locale: Locale = .autoupdatingCurrent,
                     timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter.string(from: date)
    }
}
