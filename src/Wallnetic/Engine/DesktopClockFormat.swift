import CoreGraphics
import Foundation

/// Time and date text for the desktop clock, in Wallnetic's language, English,
/// with the region's formats and the user's 12/24-hour choice. macOS gives an
/// English-only app an English locale for the user's region (en_TR on a
/// Turkish system), and `Locale.autoupdatingCurrent` carries the 12/24-hour
/// choice. Formatters are made per call, at most once per update of all
/// displays, so a changed region, time zone or clock setting applies at the
/// next update.
enum DesktopClockFormat {
    /// Hours and minutes in the locale's hour cycle. Never seconds, even from
    /// a custom short time format, because the clock changes once a minute.
    static func time(_ date: Date, locale: Locale = .autoupdatingCurrent,
                     timeZone: TimeZone = .autoupdatingCurrent) -> String {
        formatter("jmm", locale: locale, timeZone: timeZone).string(from: date)
    }

    /// Weekday, day and month in the locale's own order, e.g. "Monday 26 October".
    static func date(_ date: Date, locale: Locale = .autoupdatingCurrent,
                     timeZone: TimeZone = .autoupdatingCurrent) -> String {
        formatter("EEEEdMMMM", locale: locale, timeZone: timeZone).string(from: date)
    }

    enum Field { case time, date }

    /// The widest time and date the clock can show in `locale`, by `width`:
    /// the widest hour of a day with its widest minutes, and the widest
    /// weekday in the month whose name is widest over four years, so leap
    /// and short months count. Sized for these, the clock keeps one size
    /// through the day and the year.
    static func widest(locale: Locale, showsDate: Bool,
                       width: (String, Field) -> CGFloat) -> (time: String, date: String?) {
        let utc = TimeZone(identifier: "UTC")!
        var calendar = locale.calendar
        calendar.timeZone = utc
        // Any start will do; this year is 2026 in the Gregorian calendar.
        guard let start = calendar.dateInterval(of: .year, for: Date(timeIntervalSince1970: 1_780_000_000))?.start,
              let end = calendar.date(byAdding: .year, value: 4, to: start) else { return ("", nil) }
        func widest(_ dates: [Date], _ formatter: DateFormatter, _ field: Field) -> (date: Date, text: String)? {
            dates.map { ($0, formatter.string(from: $0)) }
                .map { (date: $0.0, text: $0.1, width: width($0.1, field)) }
                .max { $0.width < $1.width }
                .map { ($0.date, $0.text) }
        }
        let time = formatter("jmm", locale: locale, timeZone: utc)
        let hour = widest((0..<24).map { start.addingTimeInterval(TimeInterval($0) * 3_600) }, time, .time)
        let minute = hour.flatMap { hour in
            widest((0..<60).map { hour.date.addingTimeInterval(TimeInterval($0) * 60) }, time, .time)
        }
        guard showsDate else { return (minute?.text ?? "", nil) }
        // Month names, each with its last day.
        var lastDays: [Date] = []
        var month = start
        while month < end, let interval = calendar.dateInterval(of: .month, for: month) {
            lastDays.append(interval.end.addingTimeInterval(-43_200))
            month = interval.end
        }
        let longestMonth = widest(lastDays, formatter("dMMMM", locale: locale, timeZone: utc), .date)
        // Weekdays: the last seven days of that month, or all of a shorter one.
        let days = longestMonth.map { last in
            (0..<7).map { last.date.addingTimeInterval(-TimeInterval($0) * 86_400) }
                .filter { calendar.isDate($0, equalTo: last.date, toGranularity: .month) }
        } ?? []
        let date = widest(days, formatter("EEEEdMMMM", locale: locale, timeZone: utc), .date)
        return (minute?.text ?? "", date?.text)
    }

    /// The time pattern, which changes with the 12/24-hour choice even when
    /// the locale's identifier does not.
    static func timePattern(locale: Locale) -> String {
        formatter("jmm", locale: locale, timeZone: TimeZone(identifier: "UTC")!).dateFormat
    }

    private static func formatter(_ template: String, locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
