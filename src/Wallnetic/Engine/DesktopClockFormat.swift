import Foundation

/// Time and date text for the desktop clock, in the user's first preferred
/// language and region, with their 12/24-hour choice. Formatters are made per
/// call, at most once per update of all displays, so a changed language,
/// region, time zone or clock setting applies at the next update.
enum DesktopClockFormat {
    /// Hours and minutes in the locale's hour cycle. Never seconds, even from
    /// a custom short time format, because the clock changes once a minute.
    static func time(_ date: Date, locale: Locale = DesktopClockFormat.systemLocale(),
                     timeZone: TimeZone = .autoupdatingCurrent) -> String {
        formatter("jmm", locale: locale, timeZone: timeZone).string(from: date)
    }

    /// Weekday, day and month in the locale's own order, e.g. "Monday 26 October".
    static func date(_ date: Date, locale: Locale = DesktopClockFormat.systemLocale(),
                     timeZone: TimeZone = .autoupdatingCurrent) -> String {
        formatter("EEEEdMMMM", locale: locale, timeZone: timeZone).string(from: date)
    }

    /// Every hour of a day, and every weekday in every month of a year, as
    /// the clock shows them. Sized for the widest, the clock keeps its size
    /// when the hour gains a digit or the date a longer name.
    static func samples(locale: Locale) -> (times: [String], dates: [String]) {
        let utc = TimeZone(identifier: "UTC")!
        var calendar = locale.calendar
        calendar.timeZone = utc
        // Any year will do; this one is 2026 in the Gregorian calendar.
        guard let year = calendar.dateInterval(of: .year, for: Date(timeIntervalSince1970: 1_780_000_000)) else {
            return ([], [])
        }
        let timeFormatter = formatter("jmm", locale: locale, timeZone: utc)
        let dateFormatter = formatter("EEEEdMMMM", locale: locale, timeZone: utc)
        let times = (0..<24).map { timeFormatter.string(from: year.start.addingTimeInterval(TimeInterval($0) * 3_600)) }
        let months = calendar.range(of: .month, in: .year, for: year.start)?.count ?? 12
        let dates = (0..<months).flatMap { month -> [String] in
            guard let first = calendar.date(byAdding: .month, value: month, to: year.start) else { return [] }
            // The 22nd to the 28th: each weekday once, with a two-digit day.
            return (21..<28).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
                .map(dateFormatter.string(from:))
        }
        return (times, dates)
    }

    /// The clock's locale. Wallnetic's text is English only, so macOS gives it
    /// an English locale for the user's region (en_TR on a Turkish system).
    /// This keeps that locale's region and calendar and the user's 12/24-hour
    /// choice, in the user's first preferred language.
    static func systemLocale(current: Locale = .autoupdatingCurrent,
                             preferredLanguages: [String] = Locale.preferredLanguages) -> Locale {
        guard let language = preferredLanguages.first else { return current }
        var components = Locale.Components(locale: current)
        var languageComponents = Locale.Language.Components(identifier: language)
        languageComponents.region = current.region
        components.languageComponents = languageComponents
        components.hourCycle = explicitHourCycle(chosen: hourPattern(current),
                                                 regional: hourPattern(Locale(identifier: current.identifier)),
                                                 recorded: components.hourCycle)
        return Locale(components: components)
    }

    /// The user's 12/24-hour choice, or nil for the language's own default.
    /// A choice changes the current locale's hour pattern (`chosen`) from the
    /// region's default for Wallnetic's language (`regional`). A choice that
    /// matches that default shows only where macOS records it in the locale.
    static func explicitHourCycle(chosen: String, regional: String,
                                  recorded: Locale.HourCycle?) -> Locale.HourCycle? {
        guard chosen != regional else { return recorded }
        return chosen.contains(where: { $0 == "H" || $0 == "k" }) ? .zeroToTwentyThree : .oneToTwelve
    }

    private static func hourPattern(_ locale: Locale) -> String {
        DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? ""
    }

    private static func formatter(_ template: String, locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
