import XCTest
@testable import Wallnetic

/// #310: widget clock text follows the region and 12/24-hour form, case
/// changes follow the locale, and timeline minutes change on boundaries.
final class WidgetClockFormatTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    /// Monday 26 October 2026, 21:41:37 UTC.
    private let date = Date(timeIntervalSince1970: 1_793_050_897)
    private let us = Locale(identifier: "en_US")
    private let uk = Locale(identifier: "en_GB")
    private let turkish = Locale(identifier: "tr_TR")

    func testTimeFollowsTheRegionsHourCycle() {
        let twelveHour = WidgetClockFormat.time(date, locale: us, timeZone: utc)
        XCTAssertTrue(twelveHour.hasPrefix("9:41"), twelveHour)
        XCTAssertTrue(twelveHour.contains("PM"), twelveHour)
        XCTAssertEqual(WidgetClockFormat.time(date, locale: uk, timeZone: utc), "21:41")
        XCTAssertEqual(WidgetClockFormat.time(date, locale: turkish, timeZone: utc), "21:41")
    }

    func testShortDateFollowsTheRegionsOrder() throws {
        let american = WidgetClockFormat.shortDate(date, locale: us, timeZone: utc)
        let british = WidgetClockFormat.shortDate(date, locale: uk, timeZone: utc)
        for text in [american, british] {
            XCTAssertTrue(text.contains("MON") && text.contains("OCT") && text.contains("26"), text)
        }
        let americanMonth = try XCTUnwrap(american.range(of: "OCT")).lowerBound
        let americanDay = try XCTUnwrap(american.range(of: "26")).lowerBound
        XCTAssertLessThan(americanMonth, americanDay, "en_US puts the month before the day: \(american)")
        let britishMonth = try XCTUnwrap(british.range(of: "OCT")).lowerBound
        let britishDay = try XCTUnwrap(british.range(of: "26")).lowerBound
        XCTAssertLessThan(britishDay, britishMonth, "en_GB puts the day before the month: \(british)")
    }

    func testTurkishCaseChangesKeepTheDottedI() {
        let short = WidgetClockFormat.shortDate(date, locale: turkish, timeZone: utc)
        XCTAssertTrue(short.contains("EKİ"), short)
        XCTAssertFalse(short.contains("EKI"), short)
        XCTAssertEqual(WidgetClockFormat.dayName(date, locale: turkish, timeZone: utc), "pazartesi")
        XCTAssertEqual(WidgetClockFormat.monthYear(date, locale: turkish, timeZone: utc), "Ekim 2026")
        XCTAssertEqual(WidgetClockFormat.dayNumber(date, locale: turkish, timeZone: utc), "26")
    }

    func testMonthYearAndDayNameFollowTheLocale() {
        XCTAssertEqual(WidgetClockFormat.monthYear(date, locale: us, timeZone: utc), "October 2026")
        XCTAssertEqual(WidgetClockFormat.monthYear(date, locale: Locale(identifier: "ja_JP"), timeZone: utc), "2026年10月")
        XCTAssertEqual(WidgetClockFormat.dayName(date, locale: us, timeZone: utc), "monday")
    }

    func testTimelineEntriesAfterTheFirstFallOnMinuteBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let now = date.addingTimeInterval(0.25)
        let dates = WidgetClockFormat.timelineDates(from: now, count: 60, calendar: calendar)
        XCTAssertEqual(dates.count, 60)
        XCTAssertEqual(dates.first, now)
        for entry in dates.dropFirst() {
            XCTAssertEqual(calendar.component(.second, from: entry), 0)
            XCTAssertEqual(entry.timeIntervalSince1970.truncatingRemainder(dividingBy: 60), 0)
        }
        XCTAssertEqual(dates[1].timeIntervalSince(now), 22.75, accuracy: 0.001, "21:41:37.25 → 21:42:00")
        for (earlier, later) in zip(dates.dropFirst(), dates.dropFirst(2)) {
            XCTAssertEqual(later.timeIntervalSince(earlier), 60)
        }
        let reload = try XCTUnwrap(WidgetClockFormat.reloadDate(after: dates, calendar: calendar))
        XCTAssertEqual(reload, dates[1].addingTimeInterval(59 * 60), "The reload stays hourly, at a boundary")
        XCTAssertLessThanOrEqual(reload, now.addingTimeInterval(3600))
    }

    func testTimelineStartingOnABoundaryDoesNotRepeatTheMinute() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let boundary = date.addingTimeInterval(23)
        let dates = WidgetClockFormat.timelineDates(from: boundary, count: 3, calendar: calendar)
        XCTAssertEqual(dates, [boundary, boundary.addingTimeInterval(60), boundary.addingTimeInterval(120)])
        XCTAssertEqual(WidgetClockFormat.timelineDates(from: boundary, count: 0, calendar: calendar), [])
    }
}
