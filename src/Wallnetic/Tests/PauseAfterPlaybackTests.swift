import XCTest
import AppKit
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
