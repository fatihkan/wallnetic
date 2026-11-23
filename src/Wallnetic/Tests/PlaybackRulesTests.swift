import XCTest
@testable import Wallnetic

final class PlaybackRulesTests: XCTestCase {
    private let finalCut = PlaybackRuleApp(bundleID: "com.apple.FinalCut", name: "Final Cut Pro")
    private let game = PlaybackRuleApp(bundleID: "com.example.game", name: "Game")

    /// An environment in which every rule's condition holds.
    private var busy: PlaybackRulesEnvironment {
        PlaybackRulesEnvironment(frontmostBundleID: finalCut.bundleID,
                                 runningBundleIDs: [finalCut.bundleID, game.bundleID],
                                 idleSeconds: 3_600, isOnBattery: true, batteryPercent: 5,
                                 displays: [1, 2], displaysInUse: [1])
    }

    private func rules(_ change: (inout PlaybackRulesConfiguration) -> Void) -> PlaybackRulesConfiguration {
        var rules = PlaybackRulesConfiguration()
        change(&rules)
        return rules
    }

    // MARK: - Defaults

    func testEveryRuleIsOffByDefaultAndThenNothingIsHeld() {
        let rules = PlaybackRulesConfiguration()
        XCTAssertFalse(rules.isAnyRuleOn)
        XCTAssertFalse(rules.needsSampling)
        XCTAssertTrue(PlaybackRules.holds(rules, busy).isEmpty)
        XCTAssertTrue(PlaybackRules.inactiveDisplays(rules, displays: [1, 2], lastUsed: [1: 100], now: 100).isEmpty)
        XCTAssertNil(PlaybackRules.samplingInterval(rules, holds: []))
    }

    func testAnAppListWithoutItsSwitchDoesNothing() {
        let rules = rules { $0.frontApps = [finalCut]; $0.runningApps = [game] }
        XCTAssertTrue(PlaybackRules.holds(rules, busy).isEmpty)
    }

    // MARK: - Each rule on its own

    func testFrontAppRuleHoldsOnlyWhileAChosenAppIsInFront() {
        let rules = rules { $0.pausesForFrontApps = true; $0.frontApps = [finalCut] }
        XCTAssertEqual(PlaybackRules.holds(rules, busy), [.frontApp])
        var other = busy
        other.frontmostBundleID = "com.apple.finder"
        XCTAssertTrue(PlaybackRules.holds(rules, other).isEmpty, "Running in the background is not in front")
        other.frontmostBundleID = nil
        XCTAssertTrue(PlaybackRules.holds(rules, other).isEmpty)
    }

    func testRunningAppRuleHoldsWhileAnyChosenAppRuns() {
        let rules = rules { $0.pausesForRunningApps = true; $0.runningApps = [game] }
        XCTAssertEqual(PlaybackRules.holds(rules, busy), [.runningApp])
        var quit = busy
        quit.runningBundleIDs = [finalCut.bundleID]
        XCTAssertTrue(PlaybackRules.holds(rules, quit).isEmpty)
    }

    func testIdleRuleHoldsFromTheChosenTimeAndReleasesOnInput() {
        let rules = rules { $0.pausesWhenIdle = true; $0.idleMinutes = 5 }
        var environment = PlaybackRulesEnvironment()
        environment.idleSeconds = 299.9
        XCTAssertTrue(PlaybackRules.holds(rules, environment).isEmpty)
        environment.idleSeconds = 300
        XCTAssertEqual(PlaybackRules.holds(rules, environment), [.idle])
        environment.idleSeconds = 0.1
        XCTAssertTrue(PlaybackRules.holds(rules, environment).isEmpty, "Input resumes playback")
        environment.idleSeconds = .nan
        XCTAssertTrue(PlaybackRules.holds(rules, environment).isEmpty)
    }

    func testLowBatteryRuleNeedsBatteryPowerAndALevelBelowTheChoice() {
        let rules = rules { $0.pausesOnLowBattery = true; $0.lowBatteryPercent = 20 }
        var environment = PlaybackRulesEnvironment()
        environment.isOnBattery = true
        environment.batteryPercent = 19
        XCTAssertEqual(PlaybackRules.holds(rules, environment), [.lowBattery])
        environment.batteryPercent = 20
        XCTAssertTrue(PlaybackRules.holds(rules, environment).isEmpty)
        environment.batteryPercent = 5
        environment.isOnBattery = false
        XCTAssertTrue(PlaybackRules.holds(rules, environment).isEmpty, "Plugged in, a low level does not pause")
        environment.isOnBattery = true
        environment.batteryPercent = nil
        XCTAssertTrue(PlaybackRules.holds(rules, environment).isEmpty, "A Mac without a battery")
    }

    func testDisplayRuleKeepsTheDisplayInUseAndPausesTheOthersAfterTheGrace() {
        let rules = rules { $0.playsOnlyOnDisplayInUse = true }
        let grace = PlaybackRules.displayGrace
        // Both used just now: nothing pauses.
        XCTAssertTrue(PlaybackRules.inactiveDisplays(rules, displays: [1, 2], lastUsed: [1: 100, 2: 100], now: 100).isEmpty)
        // Display 2 was left; it keeps playing through the grace, then pauses.
        XCTAssertTrue(PlaybackRules.inactiveDisplays(rules, displays: [1, 2], lastUsed: [1: 100 + grace, 2: 100],
                                                     now: 100 + grace).isEmpty)
        XCTAssertEqual(PlaybackRules.inactiveDisplays(rules, displays: [1, 2], lastUsed: [1: 101 + grace, 2: 100],
                                                      now: 101 + grace), [2])
        // A display never seen in use pauses once another one is.
        XCTAssertEqual(PlaybackRules.inactiveDisplays(rules, displays: [1, 2, 3], lastUsed: [3: 50], now: 50), [1, 2])
    }

    func testDisplayRuleNeverStopsEveryDisplay() {
        let rules = rules { $0.playsOnlyOnDisplayInUse = true }
        XCTAssertTrue(PlaybackRules.inactiveDisplays(rules, displays: [1], lastUsed: [:], now: 500).isEmpty,
                      "One display is always the display in use")
        XCTAssertTrue(PlaybackRules.inactiveDisplays(rules, displays: [1, 2], lastUsed: [1: 0, 2: 0], now: 500).isEmpty,
                      "When no display is known to be in use, all keep playing")
        XCTAssertTrue(PlaybackRules.inactiveDisplays(rules, displays: [1, 2], lastUsed: [1: 0], now: .nan).isEmpty)
    }

    // MARK: - Combinations

    func testRulesCombineAndEachMapsToItsOwnReason() {
        let rules = rules {
            $0.pausesForFrontApps = true; $0.frontApps = [finalCut]
            $0.pausesForRunningApps = true; $0.runningApps = [game]
            $0.pausesWhenIdle = true
            $0.pausesOnLowBattery = true
        }
        let holds = PlaybackRules.holds(rules, busy)
        XCTAssertEqual(holds, [.frontApp, .runningApp, .idle, .lowBattery])
        XCTAssertEqual(Set(holds.map(\.pauseReason)), [.frontApp, .runningApp, .idle, .lowBattery])
        // One condition ending leaves the others in place.
        var plugged = busy
        plugged.isOnBattery = false
        XCTAssertEqual(PlaybackRules.holds(rules, plugged), [.frontApp, .runningApp, .idle])
    }

    func testRuleReasonsRankWithTheExistingOnesAndNeverHideAManualPause() {
        func status(_ reasons: [PlaybackPauseReason]) -> DisplayPlaybackStatus {
            DisplayPlaybackStatus(id: 1, displayName: "Display", hasWallpaper: true, renderer: .paused, reasons: reasons)
        }
        for reason in [PlaybackPauseReason.frontApp, .runningApp, .idle, .lowBattery, .otherDisplay] {
            XCTAssertEqual(status([reason]).title, reason.title, "The status names the rule")
            XCTAssertTrue(status([reason]).blocksResume, "Play cannot bypass an active rule")
            XCTAssertEqual(status([reason, .manual]).title, PlaybackPauseReason.manual.title)
            XCTAssertEqual(status([reason, .calm]).title, PlaybackPauseReason.calm.title)
            XCTAssertEqual(status([.timer, reason]).title, reason.title)
            XCTAssertFalse(status([reason, .manual]).detail.isEmpty)
        }
        XCTAssertEqual(status([.idle, .battery]).title, PlaybackPauseReason.battery.title)
        XCTAssertEqual(status([.lowBattery, .fullscreen]).title, PlaybackPauseReason.lowBattery.title)
        XCTAssertTrue(status([.idle]).detail.contains("Move the pointer"))
        XCTAssertTrue(status([.otherDisplay]).detail.contains("Use this display"))
    }

    func testSamplingIsOffWithoutASampledRuleAndCloseWhileIdleHolds() {
        let appsOnly = rules { $0.pausesForFrontApps = true; $0.pausesForRunningApps = true }
        XCTAssertNil(PlaybackRules.samplingInterval(appsOnly, holds: [.frontApp]), "App changes arrive as notifications")
        let battery = rules { $0.pausesOnLowBattery = true }
        XCTAssertEqual(PlaybackRules.samplingInterval(battery, holds: []), 30)
        let idle = rules { $0.pausesWhenIdle = true }
        XCTAssertEqual(PlaybackRules.samplingInterval(idle, holds: []), 2)
        XCTAssertEqual(PlaybackRules.samplingInterval(idle, holds: [.idle]), 0.5)
        let display = rules { $0.playsOnlyOnDisplayInUse = true }
        XCTAssertEqual(PlaybackRules.samplingInterval(display, holds: []), 2)
    }

    // MARK: - Settings

    func testRulesSurviveRelaunchAndAnOlderSaveKeepsDefaultsForNewKeys() throws {
        let suite = "PlaybackRulesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = PlaybackRulesSettings(defaults: defaults)
        XCTAssertEqual(settings.rules, PlaybackRulesConfiguration())
        settings.update {
            $0.pausesWhenIdle = true
            $0.idleMinutes = 10
            $0.frontApps = [finalCut]
        }
        let restored = PlaybackRulesSettings(defaults: defaults).rules
        XCTAssertTrue(restored.pausesWhenIdle)
        XCTAssertEqual(restored.idleMinutes, 10)
        XCTAssertEqual(restored.frontApps, [finalCut])
        XCTAssertFalse(restored.pausesForFrontApps, "A list alone does not turn its rule on")

        defaults.set(Data(#"{"pausesOnLowBattery":true}"#.utf8), forKey: PlaybackRulesSettings.storageKey)
        let partial = PlaybackRulesSettings(defaults: defaults).rules
        XCTAssertTrue(partial.pausesOnLowBattery)
        XCTAssertEqual(partial.lowBatteryPercent, 20)
        XCTAssertEqual(partial.idleMinutes, 5)

        defaults.set(Data("not json".utf8), forKey: PlaybackRulesSettings.storageKey)
        XCTAssertEqual(PlaybackRulesSettings(defaults: defaults).rules, PlaybackRulesConfiguration())
    }

    func testAddingAppsSkipsOnesAlreadyChosen() {
        let list = PlaybackRulesSettings.adding([game, finalCut, game], to: [finalCut])
        XCTAssertEqual(list, [finalCut, game])
    }

    // MARK: - Monitor

    func testMonitorPublishesHoldsAndClearsThemWhenTheRulesGoOff() throws {
        let suite = "PlaybackRulesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = PlaybackRulesSettings(defaults: defaults)
        var environment = busy
        let monitor = PlaybackRulesMonitor(settings: settings, sample: { _ in environment },
                                           now: { 0 }, observesSystem: false)
        XCTAssertTrue(monitor.holds.isEmpty, "Nothing is held while every rule is off")

        settings.update { $0.pausesForFrontApps = true; $0.frontApps = [finalCut] }
        XCTAssertEqual(monitor.holds, [.frontApp])
        environment.frontmostBundleID = "com.apple.finder"
        monitor.refresh()
        XCTAssertTrue(monitor.holds.isEmpty, "The hold ends with its condition")
        environment.frontmostBundleID = finalCut.bundleID
        monitor.refresh()
        XCTAssertEqual(monitor.holds, [.frontApp])
        settings.update { $0.pausesForFrontApps = false }
        XCTAssertTrue(monitor.holds.isEmpty)
    }

    func testMonitorPausesADisplayOnlyAfterItWasLeftForTheGrace() throws {
        let suite = "PlaybackRulesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = PlaybackRulesSettings(defaults: defaults)
        var time = 0.0
        var environment = PlaybackRulesEnvironment(displays: [1, 2], displaysInUse: [1])
        let monitor = PlaybackRulesMonitor(settings: settings, sample: { _ in environment },
                                           now: { time }, observesSystem: false)
        settings.update { $0.playsOnlyOnDisplayInUse = true }
        XCTAssertTrue(monitor.inactiveDisplays.isEmpty, "A display starts as in use")
        time = PlaybackRules.displayGrace + 1
        monitor.refresh()
        XCTAssertEqual(monitor.inactiveDisplays, [2])
        // The pointer moves to display 2: it plays at once, and display 1
        // keeps playing through its own grace.
        environment.displaysInUse = [2]
        monitor.refresh()
        XCTAssertTrue(monitor.inactiveDisplays.isEmpty)
        time += PlaybackRules.displayGrace + 1
        monitor.refresh()
        XCTAssertEqual(monitor.inactiveDisplays, [1])
        // A display that is disconnected is forgotten.
        environment.displays = [2]
        monitor.refresh()
        XCTAssertTrue(monitor.inactiveDisplays.isEmpty)
    }
}
