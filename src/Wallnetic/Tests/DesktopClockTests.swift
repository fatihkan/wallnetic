import XCTest
@testable import Wallnetic

/// #311: the desktop clock's visibility rule, minute scheduling, text,
/// settings, placement, view and hosting. The clock receives values only and
/// never calls a renderer.
final class DesktopClockTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    /// Monday 26 October 2026, 21:41:37 UTC.
    private let date = Date(timeIntervalSince1970: 1_793_050_897)
    /// 21:42:00 UTC, the first minute boundary after `date`.
    private let boundary = Date(timeIntervalSince1970: 1_793_050_920)
    private let us = Locale(identifier: "en_US")
    private let uk = Locale(identifier: "en_GB")
    private let german = Locale(identifier: "de_DE")
    /// Pauses that keep a still frame on screen. With the session reasons,
    /// every pause reason is in exactly one set, so a new one needs a decision.
    private let framedPauseReasons: Set<PlaybackPauseReason> = [.manual, .timer, .calm, .thermal, .battery,
                                                                .lowPower, .fullscreen]
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suite = "DesktopClockTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() {
        if let defaults, let suite { defaults.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    // MARK: - Policy

    func testEveryPauseReasonIsClassified() {
        XCTAssertEqual(DesktopClockPolicy.sessionHidingReasons, [.sleeping, .sessionInactive, .screenSaver])
        XCTAssertTrue(framedPauseReasons.isDisjoint(with: DesktopClockPolicy.sessionHidingReasons))
        XCTAssertEqual(framedPauseReasons.union(DesktopClockPolicy.sessionHidingReasons),
                       Set(PlaybackPauseReason.allCases))
    }

    func testPolicyForEveryPauseReason() {
        for reason in PlaybackPauseReason.allCases {
            let hides = DesktopClockPolicy.sessionHidingReasons.contains(reason)
            XCTAssertEqual(DesktopClockPolicy.isVisible(enabled: true, hasPresentedFrame: true, reasons: [reason]),
                           !hides, "\(reason)")
            XCTAssertEqual(DesktopClockPolicy.isVisible(enabled: true, hasPresentedFrame: true,
                                                        reasons: [.manual, reason, .battery]), !hides, "\(reason)")
            XCTAssertFalse(DesktopClockPolicy.isVisible(enabled: true, hasPresentedFrame: false, reasons: [reason]),
                           "\(reason)")
            XCTAssertFalse(DesktopClockPolicy.isVisible(enabled: false, hasPresentedFrame: true, reasons: [reason]),
                           "\(reason)")
        }
        XCTAssertTrue(DesktopClockPolicy.isVisible(enabled: true, hasPresentedFrame: true, reasons: []))
        XCTAssertFalse(DesktopClockPolicy.isVisible(enabled: true, hasPresentedFrame: false, reasons: []))
        XCTAssertFalse(DesktopClockPolicy.isVisible(enabled: false, hasPresentedFrame: true, reasons: []))
    }

    func testSessionReasonsHideEveryClockAndStopTheScheduler() throws {
        for displays in [[1], [1, 2]] as [[CGDirectDisplayID]] {
            let clock = try makeClock(displays: displays)
            for reason in DesktopClockPolicy.sessionHidingReasons {
                clock.coordinator.update(framed(displays))
                XCTAssertTrue(displays.allSatisfy(clock.isShowing), "\(reason)")
                XCTAssertTrue(clock.coordinator.isScheduling, "\(reason)")

                clock.coordinator.update(framed(displays, reasons: [.battery, reason]))
                XCTAssertFalse(displays.contains(where: clock.isShowing), "\(reason)")
                XCTAssertFalse(clock.coordinator.isScheduling, "\(reason)")
                XCTAssertFalse(clock.coordinator.isObservingChanges, "\(reason)")
                XCTAssertEqual(clock.scheduler.observerCount, 0, "\(reason)")
                XCTAssertEqual(clock.time.pendingCount, 0, "\(reason)")
            }
        }
    }

    func testTurningTheClockOffHidesEveryClockAndStopsTheScheduler() throws {
        let clock = try makeClock()
        clock.coordinator.update(framed([1, 2]))
        clock.settings.update { $0.showClock = false }
        XCTAssertFalse(clock.isShowing(1) || clock.isShowing(2))
        XCTAssertFalse(clock.coordinator.isScheduling)
        XCTAssertFalse(clock.coordinator.isObservingChanges)
        XCTAssertEqual(clock.time.pendingCount, 0)
    }

    func testFramedPausesKeepEveryClockUpdatingEachMinute() throws {
        for displays in [[1], [1, 2]] as [[CGDirectDisplayID]] {
            let clock = try makeClock(displays: displays)
            for reason in framedPauseReasons {
                clock.coordinator.update(framed(displays, reasons: [reason]))
                XCTAssertTrue(displays.allSatisfy(clock.isShowing), "\(reason)")
                let next = try XCTUnwrap(clock.scheduler.scheduledFireDate, "\(reason)")
                clock.time.fire(at: next.addingTimeInterval(0.1))
                let expected = DesktopClockFormat.time(clock.time.now, locale: uk, timeZone: utc)
                for id in displays {
                    XCTAssertEqual(clock.coordinator.view(for: id)?.content?.time, expected, "\(reason)")
                }
            }
        }
    }

    func testOnlyTheDisplayWithoutAPresentedFrameHidesItsClock() throws {
        let clock = try makeClock(displays: [1, 2, 3])
        clock.coordinator.update([.init(id: 1, hasPresentedFrame: true, reasons: []),
                                  .init(id: 2, hasPresentedFrame: false, reasons: []),
                                  .init(id: 3, hasPresentedFrame: true, reasons: [])])
        XCTAssertTrue(clock.isShowing(1))
        XCTAssertFalse(clock.isShowing(2))
        XCTAssertFalse(clock.isShowing(3), "A display without geometry shows no clock")
        XCTAssertTrue(clock.coordinator.isScheduling)

        // Without any presented frame nothing shows and nothing is scheduled.
        clock.coordinator.update([.init(id: 1, hasPresentedFrame: false, reasons: [.manual])])
        XCTAssertFalse(clock.isShowing(1) || clock.isShowing(2) || clock.isShowing(3))
        XCTAssertFalse(clock.coordinator.isScheduling)
        XCTAssertEqual(clock.time.pendingCount, 0)
    }

    // MARK: - Coordinator

    func testTurningTheClockOnShowsTheCurrentTimeAtOnce() throws {
        let clock = try makeClock(showClock: false)
        clock.coordinator.update(framed([1, 2]))
        XCTAssertFalse(clock.isShowing(1) || clock.isShowing(2))
        XCTAssertFalse(clock.coordinator.isScheduling)
        XCTAssertEqual(clock.time.pendingCount, 0)

        clock.time.now = boundary
        clock.settings.update { $0.showClock = true }
        for id in [1, 2] as [CGDirectDisplayID] {
            XCTAssertTrue(clock.isShowing(id))
            XCTAssertEqual(clock.coordinator.view(for: id)?.content?.time, "21:42")
            XCTAssertEqual(clock.coordinator.view(for: id)?.content?.date,
                           DesktopClockFormat.date(boundary, locale: uk, timeZone: utc))
        }
        XCTAssertEqual(clock.scheduler.scheduledFireDate, boundary.addingTimeInterval(60))
        XCTAssertTrue(clock.coordinator.isObservingChanges)
    }

    func testTurningTheClockOnNeverShowsItWithoutAFrame() throws {
        let clock = try makeClock(showClock: false)
        clock.coordinator.update([.init(id: 1, hasPresentedFrame: false, reasons: []),
                                  .init(id: 2, hasPresentedFrame: false, reasons: [])])
        clock.settings.update { $0.showClock = true }
        XCTAssertFalse(clock.isShowing(1) || clock.isShowing(2))
        XCTAssertFalse(clock.coordinator.isScheduling)
    }

    func testSettingChangesRedrawEveryClockInsideItsVisibleArea() throws {
        let clock = try makeClock()
        clock.coordinator.update(framed([1, 2]))
        let view = try XCTUnwrap(clock.coordinator.view(for: 1))
        let medium = try XCTUnwrap(view.content)
        XCTAssertEqual(medium.position, .topCenter)
        XCTAssertEqual(medium.visibleRect, CGRect(x: 0, y: 70, width: 1440, height: 805))
        XCTAssertNotNil(medium.date)

        clock.settings.update { $0.size = .small }
        let small = try XCTUnwrap(view.content)
        clock.settings.update { $0.size = .large; $0.position = .bottomTrailing; $0.showDate = false }
        let large = try XCTUnwrap(view.content)
        XCTAssertLessThan(small.fontSize, medium.fontSize)
        XCTAssertLessThan(medium.fontSize, large.fontSize)
        XCTAssertEqual(large.position, .bottomTrailing)
        XCTAssertNil(large.date)
        XCTAssertEqual(clock.coordinator.view(for: 2)?.content?.position, .bottomTrailing)

        let layer = try XCTUnwrap(view.layer?.sublayers?.first)
        XCTAssertTrue(large.visibleRect.contains(layer.frame), "\(layer.frame)")
        XCTAssertEqual(layer.contentsScale, 2)
    }

    func testALargeClockFitsANarrowDisplayAtEveryPosition() throws {
        // A 1080 × 1920 portrait display with the menu bar, without and with a
        // left Dock. Sized by height alone, a 12-hour Large clock would be wider.
        let visibleFrames = [CGRect(x: 0, y: 0, width: 1080, height: 1895),
                             CGRect(x: 64, y: 0, width: 1016, height: 1895)]
        let tenAM = Date(timeIntervalSince1970: 1_793_008_800), tenPM = Date(timeIntervalSince1970: 1_793_052_000)
        for backdrop in [false, true] {
            let clock = try makeClock(displays: [1], locale: us, backdrop: backdrop)
            for visibleFrame in visibleFrames {
                clock.screens.geometry[1] = .init(frame: CGRect(x: 0, y: 0, width: 1080, height: 1920),
                                                  visibleFrame: visibleFrame, scale: 2)
                for time in [tenAM, tenPM] {
                    clock.time.now = time
                    for position in DesktopClockSettings.Position.allCases {
                        clock.settings.update { $0.size = .large; $0.position = position }
                        clock.coordinator.update(framed([1]))
                        let view = try XCTUnwrap(clock.coordinator.view(for: 1))
                        let content = try XCTUnwrap(view.content)
                        let frame = try XCTUnwrap(view.layer?.sublayers?.first).frame
                        let label = "\(content.time) \(position) backdrop \(backdrop) in \(visibleFrame)"
                        XCTAssertTrue(content.visibleRect.contains(frame), "\(frame) \(label)")
                        XCTAssertLessThan(content.fontSize, (1895 * 0.13).rounded(), label)
                    }
                }
            }
        }
    }

    func testAFittedClockKeepsItsSizeAsTheTimeAndDateChange() throws {
        // Fitted to its current text, a 12-hour Large clock on a portrait
        // display would shrink at 10:00 and grow at 1:00.
        let clock = try makeClock(displays: [1], locale: us)
        clock.screens.geometry[1] = .init(frame: CGRect(x: 0, y: 0, width: 1080, height: 1920),
                                          visibleFrame: CGRect(x: 0, y: 0, width: 1080, height: 1895), scale: 2)
        clock.settings.update { $0.size = .large }
        var sizes: Set<CGFloat> = []
        // Every half hour for a week, from Monday 26 October 2026, 01:00 UTC,
        // a narrow time: the first fit must already allow for "10:00 PM".
        let monday = Date(timeIntervalSince1970: 1_792_976_400)
        for step in 0..<(7 * 48) {
            clock.time.now = monday.addingTimeInterval(TimeInterval(step) * 1_800)
            clock.coordinator.update(framed([1]))
            let content = try XCTUnwrap(clock.coordinator.view(for: 1)?.content)
            sizes.insert(content.fontSize)
            let frame = try XCTUnwrap(clock.coordinator.view(for: 1)?.layer?.sublayers?.first).frame
            // Inside the margins, allowing for the half point of rounding.
            let margin = DesktopClockLayout.margin(in: content.visibleRect) - 1
            XCTAssertTrue(content.visibleRect.insetBy(dx: margin, dy: margin).contains(frame),
                          "\(content.time) \(frame)")
        }
        XCTAssertEqual(sizes.count, 1, "\(sizes)")
        XCTAssertLessThan(try XCTUnwrap(sizes.first), (1895 * 0.13).rounded())
    }

    func testFittingKeepsTheRequestedSizeWhenItFits() {
        let visible = CGRect(x: 0, y: 70, width: 1440, height: 805)
        let fitted = DesktopClockLayout.fittedFontSize(105, in: visible) { CGSize(width: $0 * 4, height: $0 * 2) }
        XCTAssertEqual(fitted, 105)
        // Too wide: the largest size that fits inside the margins.
        let margin = DesktopClockLayout.margin(in: visible)
        let narrow = DesktopClockLayout.fittedFontSize(105, in: visible) { CGSize(width: $0 * 20, height: $0 * 2) }
        XCTAssertLessThanOrEqual(narrow * 20, visible.width - 2 * margin)
        XCTAssertGreaterThan((narrow + 1) * 20, visible.width - 2 * margin)
        // Never below the minimum.
        XCTAssertEqual(DesktopClockLayout.fittedFontSize(105, in: visible) { CGSize(width: $0 * 1_000, height: $0) }, 12)
    }

    func testEachMinuteReadsTheCurrentDisplayGeometry() throws {
        let clock = try makeClock(displays: [1])
        clock.coordinator.update(framed([1]))
        // A Dock that moves without a display change, and a scale change.
        clock.screens.geometry[1] = .init(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                          visibleFrame: CGRect(x: 80, y: 0, width: 1360, height: 875), scale: 1)
        clock.time.fire(at: boundary)
        let content = try XCTUnwrap(clock.coordinator.view(for: 1)?.content)
        XCTAssertEqual(content.visibleRect, CGRect(x: 80, y: 0, width: 1360, height: 875))
        XCTAssertEqual(content.scale, 1)
        XCTAssertEqual(content.time, "21:42")
    }

    func testRemovingADisplayRemovesOnlyItsClock() throws {
        let clock = try makeClock()
        let window = NSView()
        let removed = try XCTUnwrap(clock.coordinator.view(for: 2))
        window.addSubview(removed)
        clock.coordinator.update(framed([1, 2]))

        clock.coordinator.removeView(for: 2)
        XCTAssertNil(clock.coordinator.view(for: 2))
        XCTAssertNil(removed.superview)
        XCTAssertTrue(clock.isShowing(1))
        XCTAssertTrue(clock.coordinator.isScheduling)

        clock.coordinator.removeView(for: 1)
        XCTAssertFalse(clock.coordinator.isScheduling)
        XCTAssertFalse(clock.coordinator.isObservingChanges)
        XCTAssertEqual(clock.time.pendingCount, 0)
    }

    func testCleanupLeavesNoTimerObserverOrClock() throws {
        let clock = try makeClock()
        clock.coordinator.update(framed([1, 2]))
        XCTAssertTrue(clock.coordinator.isObservingChanges)
        XCTAssertEqual(clock.scheduler.observerCount, 6)
        let views = [clock.coordinator.view(for: 1), clock.coordinator.view(for: 2)].compactMap { $0 }
        XCTAssertEqual(views.count, 2)

        clock.coordinator.cleanup()
        XCTAssertTrue(views.allSatisfy(\.isHidden))
        XCTAssertNil(clock.coordinator.view(for: 1))
        XCTAssertFalse(clock.coordinator.isScheduling)
        XCTAssertFalse(clock.coordinator.isObservingChanges)
        XCTAssertEqual(clock.scheduler.observerCount, 0)
        XCTAssertFalse(clock.scheduler.hasPendingTimer)
        XCTAssertEqual(clock.time.pendingCount, 0)

        // Nothing restarts it afterwards.
        clock.settings.update { $0.size = .large }
        clock.coordinator.update(framed([1, 2]))
        XCTAssertFalse(clock.coordinator.isScheduling)
        XCTAssertEqual(clock.scheduler.observerCount, 0)
    }

    /// The real controller, with spy renderers on every connected display:
    /// revealing windows, turning the clock on and off, minute ticks, setting
    /// changes and status refreshes call no renderer method and change no
    /// pause reason, renderer state or playback state.
    func testTheClockNeverChangesPlayback() throws {
        let clock = try makeClock(showClock: false, displays: [])
        // Only the connected screens; a real display id can equal a test one.
        clock.screens.geometry = [:]
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            clock.screens.geometry[id] = .init(frame: screen.frame, visibleFrame: screen.visibleFrame,
                                               scale: screen.backingScaleFactor)
        }
        var spies: [ClockRendererSpy] = []
        let controller = DesktopWindowController(clock: clock.coordinator) { _ in
            let spy = ClockRendererSpy(hasPresentedFrame: false)
            spies.append(spy)
            return spy
        }
        defer { controller.cleanup() }
        let ids = Array(clock.screens.geometry.keys)
        XCTAssertEqual(spies.count, ids.count)
        // Each display's first frame reveals its window.
        for spy in spies {
            spy.hasPresentedFrame = true
            spy.onBecameReady?()
        }
        var statusReports = 0, stateReports = 0
        controller.onDisplayStatusesChanged = { _ in statusReports += 1 }
        controller.onPlaybackStateChanged = { _, _ in stateReports += 1 }
        XCTAssertEqual(statusReports, 1, "Setting the observer reports the current statuses")
        let calls = spies.map(\.calls)
        // A locked session or a running screen saver hides the clock here too.
        let canShow = DesktopClockPolicy.sessionHidingReasons.isDisjoint(with: PowerManager.shared.pauseReasons)

        clock.settings.update { $0.showClock = true }
        XCTAssertEqual(ids.allSatisfy(clock.isShowing), canShow)
        if canShow {
            for _ in 0..<3 { clock.time.fire(at: try XCTUnwrap(clock.scheduler.scheduledFireDate)) }
        }
        clock.settings.update { $0.position = .bottomLeading; $0.size = .large; $0.showDate = false }
        spies.forEach { $0.onBecameReady?() }
        controller.refreshPlaybackStatuses()
        clock.settings.update { $0.showClock = false }
        XCTAssertFalse(ids.contains(where: clock.isShowing))
        clock.settings.update { $0.showClock = true }
        controller.refreshPlaybackStatuses()

        XCTAssertEqual(spies.map(\.calls), calls, "The clock calls no renderer method")
        XCTAssertEqual(statusReports, 1, "Pause reasons and renderer states are unchanged")
        XCTAssertEqual(stateReports, 0, "Playback and Pause After states are unchanged")
    }

    func testAnUpdateThatEndsAfterAMinuteBoundaryStillUpdatesAtIt() throws {
        // Each read of the time comes 4 ms after the last, as when drawing is
        // slow. The timer must never be armed past the end of the minute shown.
        let clock = try makeClock(displays: [1])
        clock.time.readStep = 0.004
        let minuteEnds = ["21:41": boundary, "21:42": boundary.addingTimeInterval(60),
                          "21:43": boundary.addingTimeInterval(120)]
        func assertArmedByTheEndOfTheShownMinute(file: StaticString = #filePath, line: UInt = #line) throws {
            let shown = try XCTUnwrap(clock.coordinator.view(for: 1)?.content?.time, file: file, line: line)
            let end = try XCTUnwrap(minuteEnds[shown], shown, file: file, line: line)
            let armed = try XCTUnwrap(clock.scheduler.scheduledFireDate, file: file, line: line)
            XCTAssertLessThanOrEqual(armed, end, shown, file: file, line: line)
        }

        // The clock appears 3 ms before a boundary.
        clock.time.now = boundary.addingTimeInterval(-0.003)
        clock.coordinator.update(framed([1]))
        XCTAssertEqual(clock.coordinator.view(for: 1)?.content?.time, "21:41")
        XCTAssertEqual(clock.scheduler.scheduledFireDate, boundary)
        // A tick on time, then one 2 ms before the next boundary.
        clock.time.fire(at: boundary)
        try assertArmedByTheEndOfTheShownMinute()
        clock.time.fire(at: boundary.addingTimeInterval(59.998))
        try assertArmedByTheEndOfTheShownMinute()
    }

    // MARK: - Minute boundaries

    func testNextMinuteBoundaryIsStrictlyAfterTheDate() {
        let calendar = calendar(in: utc)
        XCTAssertEqual(DesktopClockPolicy.nextMinuteBoundary(after: date, calendar: calendar), boundary)
        XCTAssertEqual(DesktopClockPolicy.nextMinuteBoundary(after: boundary.addingTimeInterval(-0.001),
                                                             calendar: calendar), boundary)
        XCTAssertEqual(DesktopClockPolicy.nextMinuteBoundary(after: boundary, calendar: calendar),
                       boundary.addingTimeInterval(60))
        // A zone 5:45 ahead of UTC still changes minutes on the same instants.
        let kathmandu = self.calendar(in: TimeZone(identifier: "Asia/Kathmandu")!)
        XCTAssertEqual(DesktopClockPolicy.nextMinuteBoundary(after: date, calendar: kathmandu), boundary)
    }

    func testMinuteBoundariesAcrossMidnightAndDSTStayOneMinuteApart() {
        let cases: [(zone: String, transition: TimeInterval)] = [
            ("UTC", 1_793_059_200),              // Tuesday 27 October 2026, 00:00
            ("Europe/London", 1_792_890_000),    // 25 October 2026, 02:00 BST back to 01:00 GMT
            ("America/New_York", 1_772_953_200), // 8 March 2026, 02:00 EST forward to 03:00 EDT
        ]
        for (zone, instant) in cases {
            let calendar = calendar(in: TimeZone(identifier: zone)!)
            let transition = Date(timeIntervalSince1970: instant)
            XCTAssertEqual(DesktopClockPolicy.nextMinuteBoundary(after: transition.addingTimeInterval(-30),
                                                                 calendar: calendar), transition, zone)
            XCTAssertEqual(DesktopClockPolicy.nextMinuteBoundary(after: transition, calendar: calendar),
                           transition.addingTimeInterval(60), zone)
        }
    }

    // MARK: - Text

    func testTimeFollowsTheLocalesHourCycle() {
        let american = DesktopClockFormat.time(date, locale: us, timeZone: utc)
        XCTAssertTrue(american.hasPrefix("9:41"), american)
        XCTAssertTrue(american.contains("PM"), american)
        XCTAssertEqual(DesktopClockFormat.time(date, locale: uk, timeZone: utc), "21:41")
        XCTAssertEqual(DesktopClockFormat.time(date, locale: german, timeZone: utc), "21:41")
    }

    func testDateFollowsTheLocalesOrder() throws {
        let american = DesktopClockFormat.date(date, locale: us, timeZone: utc)
        let british = DesktopClockFormat.date(date, locale: uk, timeZone: utc)
        let germanDate = DesktopClockFormat.date(date, locale: german, timeZone: utc)
        for text in [american, british] {
            XCTAssertTrue(text.contains("Monday") && text.contains("October") && text.contains("26"), text)
            XCTAssertFalse(text.contains("2026"), "The date shows no year: \(text)")
        }
        XCTAssertTrue(germanDate.contains("Montag") && germanDate.contains("Oktober") && germanDate.contains("26."),
                      germanDate)
        XCTAssertLessThan(try start(of: "October", in: american), try start(of: "26", in: american), american)
        XCTAssertLessThan(try start(of: "26", in: british), try start(of: "October", in: british), british)
        XCTAssertLessThan(try start(of: "26", in: germanDate), try start(of: "Oktober", in: germanDate), germanDate)
    }

    func testNonLatinDigitsFollowTheLocale() {
        let arabic = Locale(identifier: "ar_EG@numbers=arab")
        let time = DesktopClockFormat.time(date, locale: arabic, timeZone: utc)
        let day = DesktopClockFormat.date(date, locale: arabic, timeZone: utc)
        XCTAssertTrue(time.contains("٤١"), time)
        XCTAssertTrue(day.contains("٢٦"), day)
        for text in [time, day] {
            XCTAssertFalse(text.contains { $0.isASCII && $0.isNumber }, text)
        }
    }

    func testTheClockUsesEnglishForTheRegion() {
        // Wallnetic's text is English only, so macOS gives it English for the
        // user's region; the clock uses that locale's names, order and hours.
        let turkey = Locale(identifier: "en_TR")
        XCTAssertEqual(DesktopClockFormat.time(date, locale: turkey, timeZone: utc), "21:41")
        let turkishDate = DesktopClockFormat.date(date, locale: turkey, timeZone: utc)
        XCTAssertTrue(turkishDate.contains("Monday") && turkishDate.contains("October"), turkishDate)
        // English in Canada counts 12 hours, unlike French there.
        let canadian = DesktopClockFormat.time(date, locale: Locale(identifier: "en_CA"), timeZone: utc)
        XCTAssertTrue(canadian.hasPrefix("9:41"), canadian)
        // English in Egypt keeps Latin digits.
        let egypt = Locale(identifier: "en_EG")
        let egyptian = DesktopClockFormat.time(date, locale: egypt, timeZone: utc) + " "
            + DesktopClockFormat.date(date, locale: egypt, timeZone: utc)
        XCTAssertTrue(egyptian.contains("9:41") && egyptian.contains("26"), egyptian)
        // An explicit 12/24-hour choice applies.
        XCTAssertEqual(DesktopClockFormat.time(date, locale: Locale(identifier: "en_CA@hours=h23"), timeZone: utc), "21:41")
        let twelveHour = DesktopClockFormat.time(date, locale: Locale(identifier: "en_TR@hours=h12"), timeZone: utc)
        XCTAssertTrue(twelveHour.hasPrefix("9:41"), twelveHour)
        // A calendar chosen in Language & Region stays.
        let persian = DesktopClockFormat.date(date, locale: Locale(identifier: "en_TR@calendar=persian"), timeZone: utc)
        XCTAssertTrue(persian.contains("Aban"), persian)
    }

    func testWidestTextHasTheLongestHourWeekdayAndMonth() {
        // Characters stand in for widths: the result is the longest hour with
        // the longest weekday and month names.
        let british = DesktopClockFormat.widest(locale: uk, showsDate: true) { text, _ in CGFloat(text.count) }
        XCTAssertEqual(british.time.count, 5, british.time)
        let date = british.date ?? ""
        XCTAssertTrue(date.contains("Wednesday") && date.contains("September"), date)
        let american = DesktopClockFormat.widest(locale: us, showsDate: false) { text, _ in CGFloat(text.count) }
        XCTAssertTrue(american.time.hasPrefix("1") && american.time.count >= 8, american.time)
        XCTAssertNil(american.date)
        // A leap month counts: Adar I appears only in a 13-month Hebrew year.
        let hebrew = DesktopClockFormat.widest(locale: Locale(identifier: "en_IL@calendar=hebrew"), showsDate: true) {
            text, field in field == .date && text.contains("Adar I") ? 1_000 : CGFloat(text.count)
        }
        XCTAssertTrue(hebrew.date?.contains("Adar I") == true, hebrew.date ?? "")
    }

    func testMidnightRollsTheTimeAndTheDayOver() {
        let lastMinute = Date(timeIntervalSince1970: 1_793_059_170) // Monday 23:59:30 UTC
        let midnight = Date(timeIntervalSince1970: 1_793_059_200)   // Tuesday 00:00 UTC
        XCTAssertEqual(DesktopClockFormat.time(lastMinute, locale: uk, timeZone: utc), "23:59")
        XCTAssertEqual(DesktopClockFormat.time(midnight, locale: uk, timeZone: utc), "00:00")
        let americanMidnight = DesktopClockFormat.time(midnight, locale: us, timeZone: utc)
        XCTAssertTrue(americanMidnight.hasPrefix("12:00") && americanMidnight.contains("AM"), americanMidnight)
        let monday = DesktopClockFormat.date(lastMinute, locale: uk, timeZone: utc)
        let tuesday = DesktopClockFormat.date(midnight, locale: uk, timeZone: utc)
        XCTAssertTrue(monday.contains("Monday") && monday.contains("26"), monday)
        XCTAssertTrue(tuesday.contains("Tuesday") && tuesday.contains("27"), tuesday)
    }

    func testTheSameInstantFollowsTheTimeZone() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(DesktopClockFormat.time(date, locale: uk, timeZone: tokyo), "06:41")
        let tokyoDay = DesktopClockFormat.date(date, locale: uk, timeZone: tokyo)
        XCTAssertTrue(tokyoDay.contains("Tuesday") && tokyoDay.contains("27"), tokyoDay)
        XCTAssertEqual(DesktopClockFormat.time(date, locale: uk, timeZone: TimeZone(identifier: "Asia/Kathmandu")!),
                       "03:26")
    }

    func testDSTTransitionsShowTheWallClock() {
        let london = TimeZone(identifier: "Europe/London")!
        XCTAssertEqual(DesktopClockFormat.time(Date(timeIntervalSince1970: 1_792_889_970), locale: uk, timeZone: london),
                       "01:59")
        XCTAssertEqual(DesktopClockFormat.time(Date(timeIntervalSince1970: 1_792_890_000), locale: uk, timeZone: london),
                       "01:00")
        let newYork = TimeZone(identifier: "America/New_York")!
        let beforeSpring = DesktopClockFormat.time(Date(timeIntervalSince1970: 1_772_953_185), locale: us,
                                                   timeZone: newYork)
        let afterSpring = DesktopClockFormat.time(Date(timeIntervalSince1970: 1_772_953_200), locale: us,
                                                  timeZone: newYork)
        XCTAssertTrue(beforeSpring.hasPrefix("1:59"), beforeSpring)
        XCTAssertTrue(afterSpring.hasPrefix("3:00"), afterSpring)
    }

    // MARK: - Settings

    func testSettingsStartOffWithTheDateAtTopCenterInMedium() {
        let preferences = DesktopClockSettings(defaults: defaults).preferences
        XCTAssertFalse(preferences.showClock)
        XCTAssertTrue(preferences.showDate)
        XCTAssertEqual(preferences.position, .topCenter)
        XCTAssertEqual(preferences.size, .medium)
        XCTAssertNil(defaults.object(forKey: DesktopClockSettings.storageKey), "Reading stores nothing")
    }

    func testSettingsPersistAcrossInstances() {
        let settings = DesktopClockSettings(defaults: defaults)
        settings.update { $0.showClock = true; $0.showDate = false; $0.position = .bottomTrailing; $0.size = .large }
        XCTAssertEqual(DesktopClockSettings(defaults: defaults).preferences,
                       .init(showClock: true, showDate: false, position: .bottomTrailing, size: .large))
    }

    func testMissingOrCorruptSettingsFallBackToTheDefaults() {
        let stored: [Any] = [
            Data("not json".utf8),
            "on",
            1,
            Data(#"{"showClock":true,"showDate":true,"position":"diagonal","size":"medium"}"#.utf8),
            Data(#"{"showClock":true}"#.utf8),
        ]
        for value in stored {
            defaults.set(value, forKey: DesktopClockSettings.storageKey)
            XCTAssertEqual(DesktopClockSettings(defaults: defaults).preferences, .init(), "\(value)")
        }
        // The next change replaces unreadable data.
        DesktopClockSettings(defaults: defaults).update { $0.showClock = true }
        XCTAssertTrue(DesktopClockSettings(defaults: defaults).preferences.showClock)
    }

    func testSettingsPublishOnlyRealChanges() {
        let settings = DesktopClockSettings(defaults: defaults)
        var published: [DesktopClockSettings.Preferences] = []
        let observer = settings.$preferences.dropFirst().sink { published.append($0) }
        settings.update { $0.showClock = true }
        settings.update { $0.showClock = true }
        settings.update { $0.position = .center }
        XCTAssertEqual(published.count, 2)
        XCTAssertEqual(published.last, .init(showClock: true, showDate: true, position: .center, size: .medium))
        withExtendedLifetime(observer) {}
    }

    // MARK: - Scheduler

    func testSchedulerFiresAtMinuteBoundariesAndReArmsAfterEachTick() {
        let time = ManualTime(date)
        let scheduler = makeScheduler(time)
        var ticks = 0
        scheduler.start(from: time.now) { ticks += 1 }
        XCTAssertEqual(ticks, 0, "Starting does not tick; the caller shows the current time")
        for minute in 1...3 {
            let expected = boundary.addingTimeInterval(TimeInterval(minute - 1) * 60)
            XCTAssertEqual(scheduler.scheduledFireDate, expected)
            XCTAssertEqual(time.pendingCount, 1)
            time.fire(at: expected.addingTimeInterval(0.15))
            XCTAssertEqual(ticks, minute)
        }
        XCTAssertEqual(time.armedDates, (0...3).map { boundary.addingTimeInterval(TimeInterval($0) * 60) })
        // A late tick, for example after sleep, arms the boundary after now.
        time.fire(at: date.addingTimeInterval(3_600.5))
        XCTAssertEqual(scheduler.scheduledFireDate,
                       DesktopClockPolicy.nextMinuteBoundary(after: time.now, calendar: calendar(in: utc)))
    }

    func testWakeClockZoneDayAndLocaleChangesRefreshAndReArm() {
        let center = NotificationCenter(), workspace = NotificationCenter()
        let time = ManualTime(date)
        let scheduler = makeScheduler(time, center: center, workspace: workspace)
        var ticks = 0
        scheduler.start(from: time.now) { ticks += 1 }
        XCTAssertEqual(scheduler.observerCount, 6)
        let changes: [(center: NotificationCenter, name: Notification.Name, clockMoves: TimeInterval)] = [
            (workspace, NSWorkspace.didWakeNotification, 3_600.25),
            (workspace, NSWorkspace.screensDidWakeNotification, 61),
            (center, .NSSystemClockDidChange, -7_200),
            (center, .NSSystemTimeZoneDidChange, 17),
            (center, .NSCalendarDayChanged, 0),
            (center, NSLocale.currentLocaleDidChangeNotification, 0),
        ]
        for (index, change) in changes.enumerated() {
            time.now.addTimeInterval(change.clockMoves)
            change.center.post(name: change.name, object: nil)
            XCTAssertEqual(ticks, index + 1, change.name.rawValue)
            XCTAssertEqual(scheduler.scheduledFireDate,
                           DesktopClockPolicy.nextMinuteBoundary(after: time.now, calendar: calendar(in: utc)),
                           change.name.rawValue)
            XCTAssertEqual(time.pendingCount, 1, "The previous timer is cancelled: \(change.name.rawValue)")
        }
    }

    func testAStoppedSchedulerHoldsNoTimerOrObserver() {
        let center = NotificationCenter(), workspace = NotificationCenter()
        let time = ManualTime(date)
        let scheduler = makeScheduler(time, center: center, workspace: workspace)
        XCTAssertFalse(scheduler.isRunning)
        XCTAssertEqual(scheduler.observerCount, 0)
        XCTAssertFalse(scheduler.hasPendingTimer)

        var ticks = 0
        scheduler.start(from: time.now) { ticks += 1 }
        scheduler.start(from: time.now) { ticks += 10 }
        XCTAssertEqual(scheduler.observerCount, 6, "A second start keeps one schedule")
        XCTAssertEqual(time.pendingCount, 1)
        time.fire(at: boundary)
        XCTAssertEqual(ticks, 10, "The latest callback ticks")

        scheduler.stop()
        XCTAssertFalse(scheduler.isRunning)
        XCTAssertEqual(scheduler.observerCount, 0)
        XCTAssertFalse(scheduler.hasPendingTimer)
        XCTAssertNil(scheduler.scheduledFireDate)
        XCTAssertEqual(time.pendingCount, 0)
        let names: [Notification.Name] = [.NSSystemClockDidChange, .NSSystemTimeZoneDidChange, .NSCalendarDayChanged,
                                          NSLocale.currentLocaleDidChangeNotification]
        names.forEach { center.post(name: $0, object: nil) }
        [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification].forEach {
            workspace.post(name: $0, object: nil)
        }
        scheduler.refresh()
        XCTAssertEqual(ticks, 10)
        XCTAssertEqual(time.pendingCount, 0)
    }

    func testATickThatHidesEveryClockLeavesNoTimer() {
        let time = ManualTime(date)
        let scheduler = makeScheduler(time)
        scheduler.start(from: time.now) { [unowned scheduler] in scheduler.stop() }
        time.fire(at: boundary)
        XCTAssertFalse(scheduler.isRunning)
        XCTAssertFalse(scheduler.hasPendingTimer)
        XCTAssertEqual(time.pendingCount, 0)
        XCTAssertEqual(time.armedDates, [boundary])
    }

    func testRunLoopScheduleFiresOnceAndCanBeCancelled() {
        var cancelledFired = false
        let cancel = DesktopClockScheduler.runLoopSchedule(Date().addingTimeInterval(0.05)) { cancelledFired = true }
        cancel()
        let fired = expectation(description: "The timer fires")
        _ = DesktopClockScheduler.runLoopSchedule(Date().addingTimeInterval(0.1)) { fired.fulfill() }
        wait(for: [fired], timeout: 2)
        XCTAssertFalse(cancelledFired)
    }

    // MARK: - Placement

    func testVisibleRectIsInWindowCoordinates() {
        let visible = DesktopClockLayout.visibleRect(screenFrame: CGRect(x: 1440, y: -200, width: 1920, height: 1080),
                                                     visibleFrame: CGRect(x: 1440, y: -130, width: 1920, height: 985))
        XCTAssertEqual(visible, CGRect(x: 0, y: 70, width: 1920, height: 985))
    }

    func testEveryPositionStaysInsideTheVisibleArea() {
        let visible = CGRect(x: 0, y: 70, width: 1440, height: 805)
        let sizes = [CGSize(width: 120, height: 61), CGSize(width: 601, height: 243), visible.size]
        for position in DesktopClockSettings.Position.allCases {
            for size in sizes {
                let origin = DesktopClockLayout.origin(for: size, in: visible, position: position)
                XCTAssertTrue(visible.contains(CGRect(origin: origin, size: size)), "\(position) \(size)")
            }
        }
    }

    func testAnchorsKeepTheirMarginFromTheVisibleEdges() {
        let visible = CGRect(x: 0, y: 70, width: 1440, height: 805)
        let size = CGSize(width: 300, height: 120)
        let margin = (visible.height * DesktopClockLayout.marginFraction).rounded()
        func frame(_ position: DesktopClockSettings.Position) -> CGRect {
            CGRect(origin: DesktopClockLayout.origin(for: size, in: visible, position: position), size: size)
        }
        XCTAssertEqual(frame(.topLeading).minX, visible.minX + margin)
        XCTAssertEqual(frame(.topLeading).maxY, visible.maxY - margin)
        XCTAssertEqual(frame(.topCenter).midX, visible.midX, accuracy: 0.5)
        XCTAssertEqual(frame(.topCenter).maxY, visible.maxY - margin)
        XCTAssertEqual(frame(.center).midX, visible.midX, accuracy: 0.5)
        XCTAssertEqual(frame(.center).midY, visible.midY, accuracy: 0.5)
        XCTAssertEqual(frame(.bottomLeading).minX, visible.minX + margin)
        XCTAssertEqual(frame(.bottomLeading).minY, visible.minY + margin)
        XCTAssertEqual(frame(.bottomCenter).midX, visible.midX, accuracy: 0.5)
        XCTAssertEqual(frame(.bottomCenter).minY, visible.minY + margin)
        XCTAssertEqual(frame(.bottomTrailing).maxX, visible.maxX - margin)
        XCTAssertEqual(frame(.bottomTrailing).minY, visible.minY + margin)
    }

    func testAClockLargerThanTheAreaKeepsItsTopLeftCorner() {
        let visible = CGRect(x: 0, y: 70, width: 400, height: 200)
        let size = CGSize(width: 600, height: 300)
        for position in DesktopClockSettings.Position.allCases {
            let origin = DesktopClockLayout.origin(for: size, in: visible, position: position)
            XCTAssertEqual(origin.x, visible.minX, "\(position)")
            XCTAssertEqual(origin.y + size.height, visible.maxY, "\(position)")
        }
    }

    // MARK: - View

    func testClockViewIsDecorativeClickThroughAndNeverAnimated() throws {
        let view = DesktopClockView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertTrue(view.isHidden)
        XCTAssertFalse(view.isAccessibilityElement())
        XCTAssertEqual(view.accessibilityChildren()?.count ?? 0, 0)
        XCTAssertNil(view.hitTest(NSPoint(x: 720, y: 450)))
        let layer = try XCTUnwrap(view.layer?.sublayers?.first)
        for key in ["contents", "bounds", "position", "hidden", "opacity", "contentsScale"] {
            XCTAssertNil(layer.action(forKey: key), key)
        }
        // No live filter, blur or backdrop behind the text.
        XCTAssertNil(layer.filters)
        XCTAssertNil(layer.backgroundFilters)
        XCTAssertNil(layer.compositingFilter)
        XCTAssertNil(view.layer?.backgroundFilters)
        XCTAssertEqual(layer.shadowOpacity, 0)
    }

    func testShowDrawsOnlyWhenTheContentChanges() throws {
        let view = DesktopClockView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        let first = clockContent()
        view.show(first)
        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(view.content, first)
        let layer = try XCTUnwrap(view.layer?.sublayers?.first)
        let drawn = try XCTUnwrap(layer.contents as AnyObject?)
        XCTAssertTrue(first.visibleRect.contains(layer.frame), "\(layer.frame)")
        XCTAssertEqual(layer.contentsScale, first.scale)

        view.show(first)
        XCTAssertTrue((layer.contents as AnyObject?) === drawn, "Unchanged content is not drawn again")
        view.hide()
        XCTAssertTrue(view.isHidden)

        var next = first
        next.time = "21:42"
        view.show(next)
        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(view.content, next)
        XCTAssertFalse((layer.contents as AnyObject?) === drawn)
    }

    func testClockImageGrowsWithTheDateAndTheBackdrop() {
        var content = clockContent()
        content.date = nil
        let plain = DesktopClockView.image(for: content).size
        var dated = content
        dated.date = "Monday 26 October"
        var backed = content
        backed.backdrop = true
        XCTAssertGreaterThan(DesktopClockView.image(for: dated).size.height, plain.height)
        XCTAssertGreaterThan(DesktopClockView.image(for: backed).size.width, plain.width)
        XCTAssertGreaterThan(DesktopClockView.image(for: backed).size.height, plain.height)
    }

    // MARK: - Hosting

    func testClockIsTheRendererViewsLastSiblingOutsideItsFilteredLayer() throws {
        var renderers: [WallpaperRenderer] = [ClockRendererSpy(), VideoRenderer()]
        if MetalVideoRenderer.isSupported { renderers.append(MetalVideoRenderer()) }
        defer { renderers.forEach { $0.stop() } }
        let size = NSSize(width: 1440, height: 900)
        for renderer in renderers {
            let name = String(describing: type(of: renderer))
            let clock = DesktopClockView(frame: .zero)
            let content = DesktopWindowController.wallpaperContent(rendererView: renderer.rendererView, size: size,
                                                                   clockView: clock)
            // The controller adds the effect overlay to the renderer view afterwards.
            let effectOverlay = NSView(frame: renderer.rendererView.bounds)
            effectOverlay.wantsLayer = true
            renderer.rendererView.addSubview(effectOverlay)
            // AppKit attaches sibling views' layers when their window displays.
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless,
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer {
                window.contentView = nil
                window.close()
            }
            window.contentView = content
            window.displayIfNeeded()

            XCTAssertEqual(content.subviews.map { ObjectIdentifier($0) },
                           [ObjectIdentifier(renderer.rendererView), ObjectIdentifier(clock)], name)
            XCTAssertFalse(clock.isDescendant(of: renderer.rendererView), name)
            XCTAssertEqual(content.frame, NSRect(origin: .zero, size: size), name)
            XCTAssertEqual(renderer.rendererView.frame, content.bounds, name)
            XCTAssertEqual(clock.frame, content.bounds, name)
            XCTAssertEqual(renderer.rendererView.autoresizingMask, [.width, .height], name)
            XCTAssertEqual(clock.autoresizingMask, [.width, .height], name)

            let clockLayer = try XCTUnwrap(clock.layer, name)
            let rendererLayer = try XCTUnwrap(renderer.rendererView.layer, name)
            let filtered = try XCTUnwrap(renderer.filterLayer ?? renderer.rendererView.layer, name)
            XCTAssertFalse(isLayer(clockLayer, inside: filtered), name)
            XCTAssertFalse(isLayer(clockLayer, inside: rendererLayer), name)
            XCTAssertTrue(clockLayer.superlayer === content.layer, name)
            XCTAssertTrue(content.layer?.sublayers?.last === clockLayer, name)
        }
    }

    func testClockViewsResizeWithTheirWindow() throws {
        let clock = try makeClock(displays: [1])
        let view = try XCTUnwrap(clock.coordinator.view(for: 1))
        XCTAssertEqual(view.autoresizingMask, [.width, .height])
        XCTAssertEqual(view.frame, NSRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertTrue(view.isHidden)
    }

    // MARK: - Helpers

    private struct Clock {
        let settings: DesktopClockSettings
        let time: ManualTime
        let screens: Screens
        let scheduler: DesktopClockScheduler
        let coordinator: DesktopClockCoordinator

        func isShowing(_ id: CGDirectDisplayID) -> Bool {
            coordinator.view(for: id).map { !$0.isHidden } ?? false
        }
    }

    /// Display 1: a 1440 × 900 Retina display with the menu bar and a bottom
    /// Dock. Display 2: a 1920 × 1080 display below and to its right. British
    /// English in UTC unless `locale` is given.
    private func makeClock(showClock: Bool = true, displays: [CGDirectDisplayID] = [1, 2],
                           locale: Locale? = nil, backdrop: Bool = false) throws -> Clock {
        let settings = DesktopClockSettings(defaults: defaults)
        settings.update { $0.showClock = showClock }
        let time = ManualTime(date)
        let screens = Screens()
        screens.geometry = [
            1: .init(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                     visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 805), scale: 2),
            2: .init(frame: CGRect(x: 1440, y: -200, width: 1920, height: 1080),
                     visibleFrame: CGRect(x: 1440, y: -200, width: 1920, height: 1055), scale: 1),
        ]
        let scheduler = makeScheduler(time)
        let locale = locale ?? uk, utc = self.utc
        let coordinator = DesktopClockCoordinator(settings: settings, scheduler: scheduler, now: { time.read() },
                                                  locale: { locale }, timeZone: { utc },
                                                  geometry: { screens.geometry[$0] }, wantsBackdrop: { backdrop })
        for id in displays {
            let size = screens.geometry[id]?.frame.size ?? NSSize(width: 800, height: 600)
            _ = coordinator.makeView(for: id, frame: NSRect(origin: .zero, size: size))
        }
        return Clock(settings: settings, time: time, screens: screens, scheduler: scheduler, coordinator: coordinator)
    }

    private func makeScheduler(_ time: ManualTime, center: NotificationCenter = NotificationCenter(),
                               workspace: NotificationCenter = NotificationCenter()) -> DesktopClockScheduler {
        let calendar = calendar(in: utc)
        return DesktopClockScheduler(now: { time.read() }, calendar: { calendar }, schedule: time.schedule,
                                     notificationCenter: center, workspaceCenter: workspace)
    }

    private func framed(_ ids: [CGDirectDisplayID],
                        reasons: [PlaybackPauseReason] = []) -> [DesktopClockCoordinator.Display] {
        ids.map { .init(id: $0, hasPresentedFrame: true, reasons: reasons) }
    }

    private func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func clockContent() -> DesktopClockView.Content {
        DesktopClockView.Content(time: "21:41", date: "Monday 26 October", fontSize: 72, position: .topCenter,
                                 visibleRect: CGRect(x: 0, y: 70, width: 1440, height: 805), scale: 2,
                                 backdrop: false)
    }

    private func start(of part: String, in text: String,
                       file: StaticString = #filePath, line: UInt = #line) throws -> String.Index {
        try XCTUnwrap(text.range(of: part), "\(part) in \(text)", file: file, line: line).lowerBound
    }

    private func isLayer(_ layer: CALayer, inside ancestor: CALayer) -> Bool {
        var current: CALayer? = layer
        while let next = current {
            if next === ancestor { return true }
            current = next.superlayer
        }
        return false
    }
}

/// A settable clock and timers that fire only when a test says so.
private final class ManualTime {
    var now: Date
    /// How far the time moves on after each read, as while drawing.
    var readStep: TimeInterval = 0
    private(set) var armedDates: [Date] = []
    private var pending: [Int: () -> Void] = [:]
    private var nextID = 0

    init(_ now: Date) { self.now = now }

    var pendingCount: Int { pending.count }

    /// The time, as the clock reads it.
    func read() -> Date {
        defer { now.addTimeInterval(readStep) }
        return now
    }

    var schedule: DesktopClockScheduler.Schedule {
        { date, action in
            let id = self.nextID
            self.nextID += 1
            self.armedDates.append(date)
            self.pending[id] = action
            return { self.pending[id] = nil }
        }
    }

    /// Moves the clock to `date` and fires the armed timer.
    func fire(at date: Date) {
        now = date
        guard let entry = pending.min(by: { $0.key < $1.key }) else { return XCTFail("No timer is armed") }
        pending[entry.key] = nil
        entry.value()
    }
}

/// Display geometry a test can change between ticks.
private final class Screens {
    var geometry: [CGDirectDisplayID: DesktopClockCoordinator.Geometry] = [:]
}

/// Records every renderer call; the clock must make none.
private final class ClockRendererSpy: WallpaperRenderer {
    let playbackMonitor = RendererPlaybackMonitor()
    let rendererView: NSView
    let filterLayer: CALayer?
    var hasPresentedFrame: Bool
    var onBecameReady: (() -> Void)?
    let currentPlaybackTime: TimeInterval? = nil
    let currentPlaybackRate: Float = 0
    private(set) var calls: [String] = []

    init(hasPresentedFrame: Bool = true) {
        let view = NSView()
        view.wantsLayer = true
        let videoLayer = CALayer()
        view.layer?.addSublayer(videoLayer)
        rendererView = view
        filterLayer = videoLayer
        self.hasPresentedFrame = hasPresentedFrame
    }

    func loadVideo(url: URL, trim: PlaybackTrim?) { calls.append(#function) }
    func applyTrim(_ trim: PlaybackTrim?) { calls.append(#function) }
    func play() { calls.append(#function) }
    func pause() { calls.append(#function) }
    func stop() { calls.append(#function) }
    func applyPerformanceMode(_ mode: PerformanceManager.PerformanceMode) { calls.append(#function) }
    func recoverPlayback() { calls.append(#function) }
    func maintainPlayback() { calls.append(#function) }
}
