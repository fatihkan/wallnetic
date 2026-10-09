import XCTest
import AppKit
@testable import Wallnetic

@MainActor
final class WallpaperScheduleTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var date = Date(timeIntervalSince1970: 0)
    private var library: [Wallpaper] = []
    private var applied: [String] = []
    private var missing = Set<String>()
    private var stoppedCompetitor = 0
    private var zone = "UTC"

    override func setUpWithError() throws {
        suite = "WallpaperScheduleTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        date = instant("2026-10-09T09:00:00Z")
        library = ["first", "second", "third"].map { Wallpaper(url: URL(fileURLWithPath: "/schedule-fixture/\($0).mp4")) }
        applied = []
        missing = []
        stoppedCompetitor = 0
        zone = "UTC"
    }
    override func tearDownWithError() throws { defaults.removePersistentDomain(forName: suite) }

    private func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func calendar(_ zone: String = "UTC") -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: zone)!
        return value
    }
    private func range(_ start: Int, _ end: Int, _ index: Int = 0) -> DailyWallpaperRange {
        DailyWallpaperRange(name: "Range \(index)", startMinute: start, endMinute: end, wallpaperPath: library[index].url.path)
    }
    private func item(_ index: Int, _ seconds: Int) -> TimedWallpaperItem {
        TimedWallpaperItem(name: library[index].name, wallpaperPath: library[index].url.path, durationSeconds: seconds)
    }
    private func daily() -> TimeOfDayManager {
        TimeOfDayManager(defaults: defaults, library: { self.library }, apply: { self.applied.append($0.url.path) },
            stopCompeting: { self.stoppedCompetitor += 1 }, now: { self.date }, calendar: { self.calendar(self.zone) },
            fileExists: { !self.missing.contains($0.path) }, observesSystem: false)
    }
    private func playlist() -> PlaylistManager {
        PlaylistManager(defaults: defaults, library: { self.library }, currentPath: { self.library.first?.url.path },
            collectionItems: { _ in Array(self.library.suffix(2)) }, apply: { self.applied.append($0.url.path) },
            stopCompeting: { self.stoppedCompetitor += 1 }, now: { self.date },
            fileExists: { !self.missing.contains($0.path) }, observesSystem: false)
    }

    func testAdjacentAndMidnightRangesHaveExclusiveEnds() throws {
        let night = range(1260, 360), day = range(360, 1260, 1)
        try DailyWallpaperSchedule.validate([night, day])
        XCTAssertTrue(night.contains(minute: 0))
        XCTAssertTrue(night.contains(minute: 1439))
        XCTAssertFalse(night.contains(minute: 360))
        XCTAssertTrue(day.contains(minute: 360))
        XCTAssertFalse(day.contains(minute: 1260))
        XCTAssertEqual(night.durationMinutes, 540)
        try DailyWallpaperSchedule.validate([range(0, 1440)])
        XCTAssertEqual(range(0, 1440).durationMinutes, 1440)
    }
    func testOverlapsAndInvalidRangesAreRejected() {
        for ranges in [[range(60, 60)], [range(-1, 120)], [range(0, 1441)],
                       [range(1440, 60)], [range(0, 1440), range(60, 120)],
                       [range(1260, 360), range(300, 600)], [range(0, 120), range(119, 240)]] {
            XCTAssertThrowsError(try DailyWallpaperSchedule.validate(ranges))
        }
        let duplicate = range(0, 60)
        XCTAssertThrowsError(try DailyWallpaperSchedule.validate([duplicate, duplicate]))
        XCTAssertThrowsError(try DailyWallpaperSchedule.validate((0..<97).map { range($0, $0 + 1) }))
    }
    func testTimelineMovementPreservesDurationAndWraps() {
        let moved = DailyWallpaperSchedule.moving(range(1320, 1440), by: 90)
        XCTAssertEqual(moved.startMinute, 1410)
        XCTAssertEqual(moved.endMinute, 90)
        XCTAssertEqual(moved.durationMinutes, 120)
        XCTAssertEqual(DailyWallpaperSchedule.moving(range(30, 90), by: -60).startMinute, 1410)
        let full = range(0, 1440)
        XCTAssertEqual(DailyWallpaperSchedule.moving(full, by: 60), full)
        XCTAssertEqual(DailyWallpaperSchedule.moving(range(30, 90), by: Int.max).durationMinutes, 60)
    }
    func testAccessibleTimeFieldsValidateBoundaries() {
        XCTAssertEqual(DailyWallpaperRange.parseTime("09:05"), 545)
        XCTAssertEqual(DailyWallpaperRange.parseTime("24:00", allowsEndOfDay: true), 1440)
        for invalid in ["24:00", "23:60", "-1:00", "12:", ":00", "9:0x", "NaN", "1:2:3"] {
            XCTAssertNil(DailyWallpaperRange.parseTime(invalid))
        }
        XCTAssertNil(DailyWallpaperRange.parseTime("24:01", allowsEndOfDay: true))
    }
    func testDSTSkippedAndRepeatedMinutesFollowLocalClock() {
        let ranges = [range(60, 120), range(120, 180, 1), range(180, 240, 2)]
        let ny = calendar("America/New_York")
        func selected(_ time: String) -> String? { DailyWallpaperSchedule.active(in: ranges, at: instant(time), calendar: ny)?.wallpaperPath }
        XCTAssertEqual(selected("2026-03-08T06:59:00Z"), library[0].url.path)
        XCTAssertEqual(selected("2026-03-08T07:00:00Z"), library[2].url.path)
        XCTAssertEqual(selected("2026-11-01T05:30:00Z"), library[0].url.path)
        XCTAssertEqual(selected("2026-11-01T06:30:00Z"), library[0].url.path)
    }
    func testLegacyDailyMigrationKeepsCustomTimesAndAllPaths() throws {
        let slots = ["morning", "afternoon", "evening", "night"]
        for (index, slot) in slots.enumerated() {
            defaults.set([5, 11, 16, 22][index], forKey: "tod.\(slot)Hour")
            defaults.set("/old/\(slot).mp4", forKey: "tod.\(slot)WallpaperPath")
        }
        let manager = daily()
        XCTAssertEqual(manager.ranges.map(\.startMinute), [300, 660, 960, 1320])
        XCTAssertEqual(manager.ranges.map(\.wallpaperPath), slots.map { "/old/\($0).mp4" })
        XCTAssertEqual(daily().ranges, manager.ranges, "Migration runs only once; IDs remain stable")
        XCTAssertNil(manager.migrationNotice)
        XCTAssertTrue(applied.isEmpty, "Initialization must not play before the delegate is wired")
        defaults.removeObject(forKey: TimeOfDayManager.documentKey)
        defaults.set(25, forKey: "tod.morningHour")
        let repaired = daily()
        XCTAssertEqual(repaired.ranges.map(\.startMinute), [360, 720, 1020, 1260])
        XCTAssertEqual(repaired.ranges.map(\.wallpaperPath), manager.ranges.map(\.wallpaperPath))
        XCTAssertNotNil(repaired.migrationNotice)
        XCTAssertEqual(defaults.integer(forKey: "tod.morningHour"), 25, "Legacy input stays intact")
    }
    func testDailyRestoreWakeAndTimeZonePickCurrentRangeOnce() {
        let manager = daily()
        XCTAssertTrue(manager.save([range(0, 720), range(720, 1440, 1)]))
        defaults.set(true, forKey: "tod.enabled")
        let restored = daily()
        restored.start(restoring: true)
        XCTAssertEqual(applied, [library[0].url.path])
        restored.evaluate()
        XCTAssertEqual(applied.count, 1)
        zone = "Asia/Tokyo" // Same instant, now 18:00.
        restored.evaluate()
        XCTAssertEqual(applied.last, library[1].url.path)
        date = instant("2026-10-10T01:00:00Z")
        restored.evaluate() // Wake at 10:00, not each missed range.
        XCTAssertEqual(applied, [library[0].url.path, library[1].url.path, library[0].url.path])
    }
    func testDailyGapMissingAndRemovedPathsKeepVisibleFallback() {
        let manager = daily()
        XCTAssertTrue(manager.save([range(540, 600), range(720, 780, 1)]))
        manager.start()
        date = instant("2026-10-09T10:00:00Z")
        manager.evaluate()
        XCTAssertTrue(manager.status.contains("No range"))
        XCTAssertEqual(applied.count, 1)
        date = instant("2026-10-09T12:00:00Z")
        missing.insert(library[1].url.path)
        manager.evaluate()
        XCTAssertTrue(manager.status.contains("missing"))
        XCTAssertEqual(applied.count, 1)
        manager.removeWallpaperPaths([library[1].url.path])
        XCTAssertEqual(manager.ranges.count, 2)
        XCTAssertEqual(manager.ranges[1].wallpaperPath, "")
        XCTAssertTrue(manager.status.contains("unassigned"))
    }
    func testDailyRepeatedManualChoiceExtendsHoldAcrossRelaunch() {
        let manager = daily()
        XCTAssertTrue(manager.save([range(0, 1440)]))
        manager.start()
        manager.onManualChange()
        date.addTimeInterval(1200)
        manager.onManualChange()
        let deadline = date.addingTimeInterval(1800)
        let restored = daily()
        restored.start(restoring: true)
        date.addTimeInterval(700)
        restored.evaluate()
        XCTAssertEqual(applied.count, 1, "The first deadline cannot release the newer manual choice")
        XCTAssertEqual(restored.manualOverrideUntil, deadline)
        date = deadline
        restored.evaluate()
        XCTAssertEqual(applied.count, 2)
        XCTAssertNil(restored.manualOverrideUntil)
        restored.onManualChange()
        restored.resumeNow()
        XCTAssertEqual(applied.count, 3)
    }
    func testDailyRejectedSavePreservesDataAndPlayback() {
        let manager = daily()
        XCTAssertTrue(manager.save([range(0, 1440)]))
        let data = defaults.data(forKey: TimeOfDayManager.documentKey)
        manager.start()
        XCTAssertFalse(manager.save(range(60, 120, 1)))
        XCTAssertEqual(defaults.data(forKey: TimeOfDayManager.documentKey), data)
        XCTAssertEqual(applied.count, 1)
        XCTAssertNotNil(manager.error)
        XCTAssertEqual(stoppedCompetitor, 1)
        manager.stop()
        manager.evaluate()
        XCTAssertEqual(applied.count, 1)
    }
    func testCorruptDailyDocumentIsKeptUntilExplicitReplacement() {
        let bad = Data("not json".utf8)
        defaults.set(bad, forKey: TimeOfDayManager.documentKey)
        let manager = daily()
        manager.start(restoring: true)
        XCTAssertTrue(applied.isEmpty)
        XCTAssertNotNil(manager.error)
        XCTAssertEqual(defaults.data(forKey: TimeOfDayManager.documentKey), bad)
        XCTAssertTrue(manager.save([range(0, 1440)]))
        XCTAssertEqual(defaults.data(forKey: TimeOfDayManager.documentKey + ".recoveryBackup"), bad)
        XCTAssertEqual(applied.count, 1)
    }
    func testUnequalDurationsLoopAndSkipMissedCycles() {
        let anchor = date
        for (offset, expected, remaining) in [(0.0, 0, 10.0), (9.5, 0, 0.5), (10, 1, 20), (30, 2, 30), (60, 0, 10), (600_035, 2, 25)] {
            XCTAssertEqual(TimedPlaylistPosition.resolve(durations: [10, 20, 30], anchor: anchor, now: anchor.addingTimeInterval(offset)),
                           TimedPlaylistPosition(index: expected, secondsRemaining: remaining))
        }
        XCTAssertEqual(TimedPlaylistPosition.resolve(durations: [10], anchor: anchor, now: anchor.addingTimeInterval(-100))?.index, 0)
    }
    func testInvalidDurationsAndNonFiniteDatesAreRejected() {
        for durations in [[], [0], [-1], [86401], [Int.max]] {
            XCTAssertNil(TimedPlaylistPosition.resolve(durations: durations, anchor: date, now: date))
        }
        XCTAssertNil(TimedPlaylistPosition.resolve(durations: [10], anchor: date, now: Date(timeIntervalSince1970: .infinity)))
        XCTAssertNil(DailyWallpaperSchedule.active(in: [range(0, 1440)], at: Date(timeIntervalSince1970: .nan), calendar: calendar()))
        XCTAssertThrowsError(try TimedWallpaperItem.validate([item(0, 0)]))
        XCTAssertThrowsError(try TimedWallpaperItem.validate((0..<501).map { _ in item(0, 10) }))
        let duplicate = item(0, 10)
        XCTAssertThrowsError(try TimedWallpaperItem.validate([duplicate, duplicate]))
    }
    func testLegacyPlaylistSelectionsSeedIndividualDurationsWithoutChangingKeys() {
        let id = UUID().uuidString
        defaults.set("collection", forKey: "playlist.source")
        defaults.set(id, forKey: "playlist.collectionID")
        defaults.set("sequential", forKey: "playlist.order")
        defaults.set(900, forKey: "playlist.intervalSeconds")
        let manager = playlist()
        XCTAssertFalse(manager.usesItemDurations)
        XCTAssertEqual(manager.sourceWallpapers().map(\.url), library.suffix(2).map(\.url))
        XCTAssertTrue(manager.setUsesItemDurations(true))
        XCTAssertEqual(manager.items.map(\.wallpaperPath), library.suffix(2).map { $0.url.path })
        XCTAssertEqual(manager.items.map(\.durationSeconds), [900, 900])
        XCTAssertTrue(manager.setUsesItemDurations(false))
        XCTAssertEqual(defaults.string(forKey: "playlist.collectionID"), id)
        XCTAssertEqual(defaults.string(forKey: "playlist.source"), "collection")
        XCTAssertEqual(defaults.string(forKey: "playlist.order"), "sequential")
        XCTAssertEqual(defaults.integer(forKey: "playlist.intervalSeconds"), 900)
    }
    func testPlaylistRestartUsesPersistedElapsedAnchor() {
        let manager = playlist()
        XCTAssertTrue(manager.saveItems([item(0, 10), item(1, 20), item(2, 30)]))
        XCTAssertTrue(manager.setUsesItemDurations(true))
        manager.start()
        date.addTimeInterval(600_035)
        let restored = playlist()
        restored.start(restoring: true)
        XCTAssertEqual(applied, [library[0].url.path, library[2].url.path])
        restored.evaluate()
        XCTAssertEqual(applied.count, 2)
        date.addTimeInterval(25)
        restored.evaluate()
        XCTAssertEqual(applied.last, library[0].url.path)
    }
    func testPlaylistMissingItemsAreSkippedAndRemovalKeepsPlaceholder() {
        let manager = playlist()
        XCTAssertTrue(manager.saveItems([item(0, 10), item(1, 20), item(2, 30)]))
        XCTAssertTrue(manager.setUsesItemDurations(true))
        missing.insert(library[0].url.path)
        manager.start()
        XCTAssertEqual(applied.last, library[1].url.path)
        XCTAssertTrue(manager.status.contains("1 unavailable"))
        manager.removeWallpaperPaths([library[1].url.path])
        XCTAssertEqual(manager.items[1].wallpaperPath, "")
        XCTAssertEqual(manager.items[1].name, library[1].name)
        XCTAssertEqual(applied.last, library[2].url.path)
        missing.insert(library[2].url.path)
        manager.evaluate()
        XCTAssertTrue(manager.status.contains("Current wallpaper kept"))
        XCTAssertEqual(applied.count, 2)
    }
    func testPlaylistHoldPersistsAndCycleContinuesWhileHeld() {
        let manager = playlist()
        XCTAssertTrue(manager.saveItems([item(0, 1000), item(1, 2000)]))
        XCTAssertTrue(manager.setUsesItemDurations(true))
        manager.start()
        manager.onManualChange()
        date.addTimeInterval(1200)
        manager.onManualChange()
        date.addTimeInterval(700)
        let restored = playlist()
        restored.start(restoring: true)
        XCTAssertEqual(applied.count, 1)
        restored.resumeNow()
        XCTAssertEqual(applied.last, library[1].url.path)
        XCTAssertNil(restored.manualOverrideUntil)
        restored.onManualChange()
        date.addTimeInterval(1800)
        restored.evaluate()
        XCTAssertEqual(applied.last, library[0].url.path)
        XCTAssertNil(restored.manualOverrideUntil)
    }
    func testSourceShuffleOrderSurvivesRelaunchAndClockRollback() throws {
        defaults.set(10, forKey: "playlist.intervalSeconds")
        let manager = playlist()
        manager.start()
        let first = try XCTUnwrap(defaults.data(forKey: PlaylistManager.progressKey))
        let order = try JSONDecoder().decode(PlaylistPlaybackProgress.self, from: first).orderedPaths
        XCTAssertEqual(Set(order), Set(library.map { $0.url.path }))
        XCTAssertNotEqual(order[0], library[0].url.path, "Explicit start chooses another item")
        date.addTimeInterval(15)
        let restored = playlist()
        restored.start(restoring: true)
        XCTAssertEqual(applied.last, order[1])
        XCTAssertEqual(defaults.data(forKey: PlaylistManager.progressKey), first)
        date.addTimeInterval(-100)
        restored.evaluate()
        XCTAssertEqual(applied.last, order[0])
        let progress = try JSONDecoder().decode(PlaylistPlaybackProgress.self, from: XCTUnwrap(defaults.data(forKey: PlaylistManager.progressKey)))
        XCTAssertEqual(progress.anchor, date)
    }
    func testPlaylistEditsReorderAndRestartCycleWithoutLosingDurations() {
        let manager = playlist()
        let entries = [item(0, 10), item(1, 20)]
        XCTAssertTrue(manager.saveItems(entries))
        XCTAssertTrue(manager.setUsesItemDurations(true))
        manager.start()
        manager.move(entries[1].id, by: -1)
        XCTAssertEqual(manager.items.map(\.durationSeconds), [20, 10])
        XCTAssertEqual(applied.last, library[1].url.path)
        let stored = defaults.data(forKey: PlaylistManager.documentKey)
        XCTAssertFalse(manager.save(item(2, 0)))
        XCTAssertEqual(defaults.data(forKey: PlaylistManager.documentKey), stored)
        manager.remove(entries[1].id)
        XCTAssertEqual(applied.last, library[0].url.path)
        XCTAssertEqual(stoppedCompetitor, 1)
        manager.stop()
        date.addTimeInterval(100)
        manager.evaluate()
        XCTAssertEqual(applied.count, 3)
    }
    func testEnablingCustomDurationsDoesNotApplyOldSourceFirst() {
        let manager = playlist()
        manager.start()
        applied.removeAll()
        XCTAssertTrue(manager.setUsesItemDurations(true))
        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied.first, library[0].url.path)
    }
    func testCorruptPlaylistSettingsHaveRecoverableBackup() {
        let bad = Data("invalid json".utf8)
        defaults.set(bad, forKey: PlaylistManager.documentKey)
        defaults.set(bad, forKey: PlaylistManager.progressKey)
        defaults.set(true, forKey: "playlist.useItemDurations")
        let manager = playlist()
        manager.start(restoring: true)
        XCTAssertTrue(applied.isEmpty)
        XCTAssertEqual(defaults.data(forKey: PlaylistManager.documentKey), bad)
        XCTAssertTrue(manager.saveItems([item(0, 10)]))
        XCTAssertEqual(defaults.data(forKey: PlaylistManager.documentKey + ".recoveryBackup"), bad)
        XCTAssertEqual(defaults.data(forKey: PlaylistManager.progressKey + ".recoveryBackup"), bad)
        XCTAssertEqual(applied.count, 1)
    }
    func testLegacySourcesLargerThanCustomEditorLimitStillRotate() {
        library = (0..<501).map { Wallpaper(url: URL(fileURLWithPath: "/schedule-fixture/\($0).mp4")) }
        defaults.set("sequential", forKey: "playlist.order")
        defaults.set(10, forKey: "playlist.intervalSeconds")
        let manager = playlist()
        manager.start(restoring: true)
        date.addTimeInterval(5000)
        manager.evaluate()
        XCTAssertEqual(applied.last, library[500].url.path)
        XCTAssertFalse(manager.setUsesItemDurations(true), "Custom editor limit must not truncate existing selections")
        XCTAssertFalse(manager.usesItemDurations)
    }
    func testRestoreResolvesConflictingLegacyModesByLastOwner() {
        defaults.set(true, forKey: "tod.enabled")
        defaults.set(true, forKey: "playlist.enabled")
        defaults.set("playlist", forKey: WallpaperAutomation.ownerKey)
        let a = daily(), b = playlist()
        WallpaperAutomation.restore(daily: a, playlist: b, defaults: defaults)
        XCTAssertFalse(a.isEnabled)
        XCTAssertTrue(b.isEnabled)
        defaults.set(true, forKey: "tod.enabled")
        defaults.removeObject(forKey: WallpaperAutomation.ownerKey)
        let c = daily(), d = playlist()
        WallpaperAutomation.restore(daily: c, playlist: d, defaults: defaults)
        XCTAssertTrue(c.isEnabled)
        XCTAssertFalse(d.isEnabled)
    }
    func testRuntimeReactsToClockAndWakeAndStopsObservers() {
        let runtime = WallpaperAutomationRuntime()
        var evaluations = 0
        runtime.start { evaluations += 1 }
        NotificationCenter.default.post(name: .NSSystemClockDidChange, object: nil)
        NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        XCTAssertEqual(evaluations, 5)
        runtime.stop()
        NotificationCenter.default.post(name: .NSSystemClockDidChange, object: nil)
        XCTAssertEqual(evaluations, 5)
    }
}
