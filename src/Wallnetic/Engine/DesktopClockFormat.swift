import Foundation

/// Time and date text for the desktop clock, in the language, region and
/// 12/24-hour setting the menu bar clock uses. Formatters are made per call,
/// at most once per update of all displays, so a changed language, region,
/// time zone or clock setting applies at the next update.
enum DesktopClockFormat {
    /// Hours and minutes in the locale's hour cycle. Never seconds, even from
    /// a custom short time format, because the clock changes once a minute.
    static func time(_ date: Date, locale: Locale = DesktopClockFormat.systemLocale(),
                     timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter.string(from: date)
    }

    /// Weekday, day and month in the locale's own order, e.g. "Monday 26 October".
    static func date(_ date: Date, locale: Locale = DesktopClockFormat.systemLocale(),
                     timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter.string(from: date)
    }

    /// The locale the menu bar formats with. Wallnetic's text is English
    /// only, so its own current locale is English for the user's region (en_TR
    /// on a Turkish system). This keeps that locale's region, calendar and an
    /// explicit 12/24-hour choice, in the user's first preferred language.
    static func systemLocale(current: Locale = .autoupdatingCurrent,
                             preferredLanguages: [String] = Locale.preferredLanguages) -> Locale {
        guard let language = preferredLanguages.first else { return current }
        var components = Locale.Components(locale: current)
        var languageComponents = Locale.Language.Components(identifier: language)
        languageComponents.region = current.region
        components.languageComponents = languageComponents
        return Locale(components: components)
    }
}
