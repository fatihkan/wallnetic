import XCTest
import AppKit
import Combine
@testable import Wallnetic

final class PauseAfterPlaybackTests: XCTestCase {
    private let firstURL = URL(fileURLWithPath: "/fixtures/first.mp4")
    private let secondURL = URL(fileURLWithPath: "/fixtures/second.mp4")

    func testPreferencesPersistInheritAndNeverAsDifferentChoices() throws {
        let suite = "PauseAfterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = PauseAfterSettings(defaults: defaults)
        XCTAssertNil(settings.preferences.duration(for: firstURL))
        XCTAssertFalse(settings.preferences.replayWhenDesktopClears)
        settings.setDefault(seconds: 30)
        settings.setOverride(seconds: 0, for: firstURL)
        settings.setOverride(seconds: 47, for: secondURL)
        settings.setReplayWhenDesktopClears(true)
        let restored = PauseAfterSettings(defaults: defaults)
        XCTAssertNil(restored.preferences.duration(for: firstURL))
        XCTAssertEqual(restored.preferences.duration(for: secondURL), 47)
        XCTAssertTrue(restored.preferences.replayWhenDesktopClears)
        restored.setOverride(seconds: nil, for: firstURL)
        XCTAssertEqual(restored.preferences.duration(for: firstURL), 30)
        restored.setDefault(seconds: 60)
        XCTAssertEqual(restored.preferences.duration(for: firstURL), 60)
        XCTAssertEqual(restored.preferences.duration(for: secondURL), 47)
        restored.setDefault(seconds: Int.max)
        XCTAssertNil(restored.preferences.duration(for: firstURL))
        defaults.set(Data("invalid".utf8), forKey: PauseAfterSettings.storageKey)
        XCTAssertEqual(PauseAfterSettings(defaults: defaults).preferences, .init())
    }

    @MainActor
    func testExpirationWaitsForAFrameAndStopsAtTheBoundaryOnce() {
        var time = 0.0
        let playback = PauseAfterPlayback(now: { time }, canPlay: { true })
        let renderer = DurationRendererSpy()
        renderer.hasPresentedFrame = false
        playback.setWallpaper(firstURL, renderer: renderer, on: 1, preferences: .init(defaultSeconds: 15))
        playback.play()
        time = 100
        playback.tick()
        XCTAssertEqual(renderer.pauses, 0, "Do not freeze an empty loading overlay")
        renderer.hasPresentedFrame = true
        playback.tick()
        time = 114.999
        playback.tick()
        XCTAssertEqual(renderer.pauses, 0)
        time = 115
        playback.tick()
        playback.tick()
        XCTAssertEqual(renderer.pauses, 1)
        XCTAssertTrue(playback.isPausedAfterDuration)
        XCTAssertFalse(playback.needsTimer)
        XCTAssertFalse(playback.shouldPlay(on: 1), "Watchdog/maintenance must stand down")
        XCTAssertTrue(renderer.hasPresentedFrame)
    }

    @MainActor
    func testDifferentDisplaysAndWallpaperChangesHaveIndependentIntervals() {
        var time = 0.0
        let playback = PauseAfterPlayback(now: { time }, canPlay: { true })
        let a = DurationRendererSpy(), b = DurationRendererSpy()
        let preferences = PauseAfterSettings.Preferences(defaultSeconds: 15, overrides: [secondURL.path: 30])
        playback.setWallpaper(firstURL, renderer: a, on: 1, preferences: preferences)
        playback.setWallpaper(secondURL, renderer: b, on: 2, preferences: preferences)
        playback.play()
        time = 15
        playback.tick()
        XCTAssertFalse(playback.shouldPlay(on: 1))
        XCTAssertTrue(playback.shouldPlay(on: 2))
        XCTAssertTrue(playback.hasActivePlayback)
        XCTAssertFalse(playback.isPausedAfterDuration)
        playback.setWallpaper(secondURL, renderer: a, on: 1, preferences: preferences)
        playback.play() // Existing apply path may ask to play again.
        time = 30
        playback.tick()
        XCTAssertFalse(playback.shouldPlay(on: 2), "Changing A must not extend B's timer")
        XCTAssertTrue(playback.shouldPlay(on: 1))
        time = 45
        playback.tick()
        XCTAssertTrue(playback.isPausedAfterDuration)
        playback.remove(1)
        playback.remove(2)
        XCTAssertFalse(playback.isPausedAfterDuration)
        XCTAssertFalse(playback.needsTimer)
    }

    @MainActor
    func testManualPauseSurvivesPowerEventsWallpaperChangesAndPreferenceEdits() {
        var allowed = true
        let playback = PauseAfterPlayback(now: { 0 }, canPlay: { allowed })
        let renderer = DurationRendererSpy()
        playback.setWallpaper(firstURL, renderer: renderer, on: 1, preferences: .init(defaultSeconds: 15))
        playback.play()
        playback.pause(manual: true)
        let plays = renderer.plays
        allowed = false
        playback.pause(manual: false)
        playback.pause(manual: false)
        playback.play()
        allowed = true
        playback.play() // Wake/unlock cannot revoke manual pause.
        playback.setWallpaper(secondURL, renderer: renderer, on: 1, preferences: .init(defaultSeconds: 30))
        playback.play()
        playback.updatePreferences(.init(defaultSeconds: 0))
        playback.replayExpiredDisplay(1)
        XCTAssertEqual(renderer.plays, plays)
        XCTAssertFalse(playback.hasActivePlayback)
        playback.play(explicit: true)
        XCTAssertTrue(playback.hasActivePlayback)
        XCTAssertFalse(playback.needsTimer)
    }

    @MainActor
    func testRepeatedPowerPausesAndSleepStartOneFreshIntervalOnAllowedResume() {
        var time = 0.0, allowed = true
        let playback = PauseAfterPlayback(now: { time }, canPlay: { allowed })
        let renderer = DurationRendererSpy()
        playback.setWallpaper(firstURL, renderer: renderer, on: 1, preferences: .init(defaultSeconds: 15))
        playback.play()
        time = 10
        allowed = false
        playback.pause(manual: false)
        playback.pause(manual: false)
        time = 1_000
        playback.play()
        XCTAssertFalse(playback.hasActivePlayback)
        allowed = true
        playback.play()
        time = 1_010
        playback.play() // A duplicate resume must not extend the interval.
        time = 1_015
        playback.tick()
        XCTAssertTrue(playback.isPausedAfterDuration)
        playback.play(explicit: true)
        XCTAssertTrue(playback.hasActivePlayback)
        time = 1_029
        playback.tick()
        XCTAssertTrue(playback.hasActivePlayback)
        time = 1_030
        playback.tick()
        XCTAssertTrue(playback.isPausedAfterDuration)
    }

    @MainActor
    func testDesktopReplayRequiresAllowedIntentAndOnlyResetsTheExpiredDisplay() {
        var time = 0.0, allowed = true
        let playback = PauseAfterPlayback(now: { time }, canPlay: { allowed })
        let a = DurationRendererSpy(), b = DurationRendererSpy()
        playback.setWallpaper(firstURL, renderer: a, on: 1, preferences: .init(defaultSeconds: 15))
        playback.setWallpaper(secondURL, renderer: b, on: 2, preferences: .init(defaultSeconds: 30))
        playback.play()
        time = 15
        playback.tick()
        allowed = false
        playback.replayExpiredDisplay(1)
        XCTAssertFalse(playback.shouldPlay(on: 1))
        allowed = true
        playback.replayExpiredDisplay(1)
        XCTAssertTrue(playback.shouldPlay(on: 1))
        time = 30
        playback.tick()
        XCTAssertTrue(playback.isPausedAfterDuration)
        playback.pause(manual: true)
        playback.replayExpiredDisplay(1)
        XCTAssertFalse(playback.hasActivePlayback)
    }

    @MainActor
    func testOverlappingHoldsKeepIntentAndFreezeTheRemainingPlaybackInterval() {
        var time = 0.0
        let playback = PauseAfterPlayback(now: { time }, canPlay: { true })
        let renderer = DurationRendererSpy()
        playback.setWallpaper(firstURL, renderer: renderer, on: 1, preferences: .init(defaultSeconds: 30))
        playback.play()
        time = 10
        playback.setHolds([.calm])
        XCTAssertTrue(playback.isRequested)
        XCTAssertFalse(playback.hasActivePlayback)
        XCTAssertFalse(playback.isPausedAfterDuration)
        XCTAssertFalse(playback.needsTimer)
        XCTAssertFalse(playback.shouldPlay(on: 1))
        XCTAssertTrue(renderer.hasPresentedFrame)
        let plays = renderer.plays
        time = 40
        playback.setHolds([.calm, .thermal])
        playback.setHolds([.thermal])
        playback.tick()
        playback.replayExpiredDisplay(1)
        XCTAssertEqual(renderer.plays, plays)
        time = 100
        playback.setHolds([])
        XCTAssertEqual(renderer.plays, plays + 1)
        time = 119.999
        playback.tick()
        XCTAssertTrue(playback.hasActivePlayback)
        time = 120
        playback.tick()
        XCTAssertTrue(playback.isPausedAfterDuration)
    }

    @MainActor
    func testHoldReleaseCannotRestartExpiredDisplaysOrAnIdleSession() {
        var time = 0.0
        let playback = PauseAfterPlayback(now: { time }, canPlay: { true })
        let a = DurationRendererSpy(), b = DurationRendererSpy()
        playback.setWallpaper(firstURL, renderer: a, on: 1, preferences: .init(defaultSeconds: 15))
        playback.setWallpaper(secondURL, renderer: b, on: 2, preferences: .init(defaultSeconds: 30))
        playback.setHolds([.calm])
        playback.setHolds([])
        XCTAssertEqual(a.plays + b.plays, 0)
        playback.play()
        time = 15
        playback.tick()
        XCTAssertTrue(playback.isExpired(on: 1))
        let aPlays = a.plays
        playback.setHolds([.thermal])
        time = 100
        playback.setHolds([])
        XCTAssertEqual(a.plays, aPlays)
        XCTAssertFalse(playback.shouldPlay(on: 1))
        XCTAssertTrue(playback.shouldPlay(on: 2))
        time = 115
        playback.tick()
        XCTAssertTrue(playback.isPausedAfterDuration)
        let allPlays = a.plays + b.plays
        playback.setHolds([.calm, .thermal])
        playback.setHolds([])
        XCTAssertEqual(a.plays + b.plays, allPlays)
        XCTAssertTrue(playback.isPausedAfterDuration)
    }

    @MainActor
    func testManualPauseDuringHoldSurvivesHoldRemovalAndSubsequentPowerResume() {
        let playback = PauseAfterPlayback(canPlay: { true })
        let renderer = DurationRendererSpy()
        playback.setWallpaper(firstURL, renderer: renderer, on: 1, preferences: .init())
        playback.play()
        playback.setHolds([.calm, .thermal])
        playback.pause(manual: true)
        let plays = renderer.plays
        playback.setHolds([.thermal])
        playback.setHolds([])
        playback.pause(manual: false)
        playback.play()
        XCTAssertEqual(renderer.plays, plays)
        XCTAssertTrue(playback.isManuallyPaused)
        playback.play(explicit: true)
        XCTAssertTrue(playback.hasActivePlayback)
    }

    @MainActor
    func testPowerAndHoldOrderingPreservesManualIntentAndAutoResumePreference() {
        for holdFirst in [true, false] {
            for releaseHoldFirst in [true, false] {
                for autoResume in [true, false] {
                    for manual in [true, false] {
                        var allowed = true
                        let playback = PauseAfterPlayback(canPlay: { allowed })
                        let renderer = DurationRendererSpy()
                        playback.setWallpaper(firstURL, renderer: renderer, on: 1, preferences: .init())
                        playback.play()
                        if manual { playback.pause(manual: true) }
                        if holdFirst { playback.setHolds([.calm, .thermal]) }
                        let owned = PowerPauseOwnership.shouldClaimPause(
                            wallpaperIsPlaying: playback.hasActivePlayback,
                            isPausedAfterDuration: playback.isPausedAfterDuration,
                            hasPlaybackResumeIntent: playback.isRequested)
                        XCTAssertEqual(owned, !manual)
                        allowed = false
                        playback.pause(manual: false)
                        if !holdFirst { playback.setHolds([.calm, .thermal]) }
                        if releaseHoldFirst {
                            playback.setHolds([])
                            XCTAssertFalse(playback.hasActivePlayback)
                        }
                        allowed = true
                        if PowerPauseOwnership.shouldResume(pausedByPower: owned, shouldBePaused: false,
                                                            respectAutoResume: true, autoResumeEnabled: autoResume) {
                            playback.play()
                        }
                        if !releaseHoldFirst {
                            XCTAssertFalse(playback.hasActivePlayback)
                            playback.setHolds([])
                        }
                        XCTAssertEqual(playback.hasActivePlayback, autoResume && !manual,
                                       "holdFirst=\(holdFirst), releaseHoldFirst=\(releaseHoldFirst), auto=\(autoResume), manual=\(manual)")
                        XCTAssertEqual(renderer.currentPlaybackRate, autoResume && !manual ? 1 : 0)
                    }
                }
            }
        }
    }

    @MainActor
    func testNewDisplaysReplacementsAndPreferenceChangesCannotBypassHolds() {
        let playback = PauseAfterPlayback(canPlay: { true })
        let a = DurationRendererSpy(), b = DurationRendererSpy()
        playback.setWallpaper(firstURL, renderer: a, on: 1, preferences: .init(defaultSeconds: 15))
        playback.play()
        playback.setHolds([.calm])
        let oldPlays = a.plays
        playback.setWallpaper(secondURL, renderer: a, on: 1, preferences: .init(defaultSeconds: 30))
        playback.setWallpaper(firstURL, renderer: b, on: 2, preferences: .init(defaultSeconds: 15))
        playback.updatePreferences(.init(defaultSeconds: 60))
        playback.play()
        playback.tick()
        XCTAssertEqual(a.plays, oldPlays)
        XCTAssertEqual(b.plays, 0)
        playback.remove(1)
        playback.setHolds([])
        XCTAssertEqual(a.plays, oldPlays)
        XCTAssertEqual(b.plays, 1)
    }

    @MainActor
    func testPowerGateStillBlocksHoldReleaseBeforeItsPauseCallbackArrives() {
        var allowed = true
        let playback = PauseAfterPlayback(canPlay: { allowed })
        let renderer = DurationRendererSpy()
        playback.setWallpaper(firstURL, renderer: renderer, on: 1, preferences: .init())
        playback.play()
        playback.setHolds([.calm])
        allowed = false
        let plays = renderer.plays
        playback.setHolds([])
        XCTAssertFalse(playback.shouldPlay(on: 1))
        XCTAssertEqual(renderer.plays, plays)
    }

    @MainActor
    func testSettingsBindingReleasesThermalAndCalmIndependently() throws {
        let suite = "CalmBindingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = CalmPlaybackSettings(defaults: defaults, center: NotificationCenter(), thermalState: { .critical })
        let playback = PauseAfterPlayback(canPlay: { true })
        let renderer = DurationRendererSpy()
        let binding = settings.$state.map(\.holds).removeDuplicates().sink { playback.setHolds($0) }
        defer { binding.cancel() }
        playback.setWallpaper(firstURL, renderer: renderer, on: 1, preferences: .init())
        playback.play()
        settings.setCalmEnabled(true)
        settings.setThermalEnabled(true)
        settings.setCalmEnabled(false)
        XCTAssertEqual(playback.holds, [.thermal])
        XCTAssertEqual(renderer.currentPlaybackRate, 0)
        settings.setThermalEnabled(false)
        XCTAssertEqual(renderer.currentPlaybackRate, 1)
    }

    func testDesktopClearNeedsStableCoveredToClearEdgeWithoutRepeating() {
        var transition = DesktopClearTransition()
        for _ in 0..<5 { XCTAssertFalse(transition.record(isClear: true)) }
        XCTAssertFalse(transition.record(isClear: false))
        XCTAssertFalse(transition.record(isClear: true), "Transient cover is ignored")
        XCTAssertFalse(transition.record(isClear: false))
        XCTAssertFalse(transition.record(isClear: false))
        XCTAssertFalse(transition.record(isClear: true))
        XCTAssertTrue(transition.record(isClear: true))
        for _ in 0..<5 { XCTAssertFalse(transition.record(isClear: true)) }
    }
}

private final class DurationRendererSpy: WallpaperRenderer {
    let playbackMonitor = RendererPlaybackMonitor()
    let rendererView = NSView()
    var hasPresentedFrame = true
    var onBecameReady: (() -> Void)?
    var filterLayer: CALayer? { nil }
    var currentPlaybackTime: TimeInterval? { 1 }
    var currentPlaybackRate: Float = 0
    var plays = 0
    var pauses = 0
    func play() { plays += 1; currentPlaybackRate = 1 }
    func pause() { pauses += 1; currentPlaybackRate = 0 }
    func stop() { currentPlaybackRate = 0; hasPresentedFrame = false }
    func loadVideo(url: URL) {}
    func maintainPlayback() {}
    func recoverPlayback() { play() }
    func applyPerformanceMode(_ mode: PerformanceManager.PerformanceMode) {}
}
