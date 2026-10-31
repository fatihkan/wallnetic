import Foundation

/// Clock and date text for the widgets. Formats follow the user's region and
/// 12/24-hour setting, and every case change uses the formatter's locale, so
/// Turkish "i" keeps its dot (#310). Keep this file included in both the
/// Wallnetic and WallneticWidget targets; the app target makes it testable.
enum WidgetClockFormat {
    /// Hours and minutes in the user's 12- or 24-hour form ("9:41 PM", "21:41").
    static func time(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Day, abbreviated month and weekday in the region's order, upper-cased.
    static func shortDate(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = formatter(template: "dMMMEEE", locale: locale, timeZone: timeZone)
        return formatter.string(from: date).uppercased(with: formatter.locale)
    }

    static func dayNumber(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        formatter(template: "d", locale: locale, timeZone: timeZone).string(from: date)
    }

    static func monthYear(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        formatter(template: "MMMMyyyy", locale: locale, timeZone: timeZone).string(from: date)
    }

    /// Full weekday name, lower-cased.
    static func dayName(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = formatter(template: "EEEE", locale: locale, timeZone: timeZone)
        return formatter.string(from: date).lowercased(with: formatter.locale)
    }

    /// The first entry shows the current minute. Every later entry falls on a
    /// minute boundary, so the widget's minute changes with the menu-bar clock
    /// instead of up to a minute later.
    static func timelineDates(from now: Date, count: Int, calendar: Calendar = .current) -> [Date] {
        guard count > 0 else { return [] }
        let minute = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        return [now] + (1..<count).compactMap { calendar.date(byAdding: .minute, value: $0, to: minute) }
    }

    /// The minute boundary after the last entry: still one reload an hour.
    static func reloadDate(after dates: [Date], calendar: Calendar = .current) -> Date? {
        dates.last.flatMap { calendar.date(byAdding: .minute, value: 1, to: $0) }
    }

    private static func formatter(template: String, locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
