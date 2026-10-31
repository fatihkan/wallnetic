import XCTest
import Combine
@testable import Wallnetic

final class ThermalPlaybackPolicyTests: XCTestCase {
    func testDisabledPolicyNeverPausesEvenUnderCriticalPressure() {
        var policy = ThermalPlaybackPolicy()
        for state in [ProcessInfo.ThermalState.nominal, .fair, .serious, .critical] {
            policy.update(enabled: false, state: state, at: 100)
            XCTAssertFalse(policy.isPaused)
            XCTAssertNil(policy.deadline)
        }
    }

    func testSeriousPressureNeedsTenContinuousSecondsAndRepeatedEventsDoNotDelayIt() {
        var policy = ThermalPlaybackPolicy()
        policy.update(enabled: true, state: .serious, at: 10)
        policy.update(enabled: true, state: .serious, at: 19.999)
        XCTAssertFalse(policy.isPaused)
        XCTAssertEqual(policy.deadline, 20)
        policy.update(enabled: true, state: .serious, at: 20)
        XCTAssertTrue(policy.isPaused)
        XCTAssertNil(policy.deadline)
    }

    func testBriefSeriousPressureDoesNotAccumulateAcrossCooling() {
        var policy = ThermalPlaybackPolicy()
        policy.update(enabled: true, state: .serious, at: 0)
        policy.update(enabled: true, state: .fair, at: 9)
        XCTAssertNil(policy.deadline)
        policy.update(enabled: true, state: .serious, at: 10)
        policy.update(enabled: true, state: .serious, at: 19)
        XCTAssertFalse(policy.isPaused)
        policy.update(enabled: true, state: .serious, at: 20)
        XCTAssertTrue(policy.isPaused)
    }

    func testCriticalPressurePausesImmediatelyAndCancelsAnyPendingTransition() {
        var policy = ThermalPlaybackPolicy()
        policy.update(enabled: true, state: .critical, at: 0)
        XCTAssertTrue(policy.isPaused)
        XCTAssertNil(policy.deadline)
        policy.update(enabled: true, state: .nominal, at: 1)
        policy.update(enabled: true, state: .critical, at: 60)
        XCTAssertTrue(policy.isPaused)
        XCTAssertNil(policy.deadline)
    }

    func testRecoveryNeedsSixtySecondsAcrossNominalAndFairStates() {
        var policy = ThermalPlaybackPolicy()
        policy.update(enabled: true, state: .critical, at: 0)
        policy.update(enabled: true, state: .fair, at: 10)
        policy.update(enabled: true, state: .nominal, at: 50)
        policy.update(enabled: true, state: .fair, at: 69.999)
        XCTAssertTrue(policy.isPaused)
        XCTAssertEqual(policy.deadline, 70)
        policy.update(enabled: true, state: .fair, at: 70)
        XCTAssertFalse(policy.isPaused)
        XCTAssertNil(policy.deadline)
    }

    func testRenewedSeriousPressureRestartsTheEntireCoolingInterval() {
        var policy = ThermalPlaybackPolicy()
        policy.update(enabled: true, state: .critical, at: 0)
        policy.update(enabled: true, state: .nominal, at: 10)
        policy.update(enabled: true, state: .serious, at: 69)
        XCTAssertNil(policy.deadline)
        policy.update(enabled: true, state: .fair, at: 70)
        policy.update(enabled: true, state: .nominal, at: 129.999)
        XCTAssertTrue(policy.isPaused)
        policy.update(enabled: true, state: .nominal, at: 130)
        XCTAssertFalse(policy.isPaused)
    }

    func testDisablingReleasesOnlyThisPolicyAndReenableStartsFresh() {
        var policy = ThermalPlaybackPolicy()
        policy.update(enabled: true, state: .critical, at: 0)
        policy.update(enabled: false, state: .critical, at: 1)
        XCTAssertFalse(policy.isPaused)
        XCTAssertNil(policy.deadline)
        policy.update(enabled: true, state: .serious, at: 2)
        XCTAssertFalse(policy.isPaused)
        XCTAssertEqual(policy.deadline, 12)
        policy.update(enabled: true, state: .critical, at: 3)
        XCTAssertTrue(policy.isPaused)
    }

    @MainActor
    func testSettingsPersistOnlyThermalOptInAndSeedCriticalStateOnRelaunch() throws {
        let suite = "CalmSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = NotificationCenter()
        let settings = CalmPlaybackSettings(defaults: defaults, center: center, thermalState: { .critical })
        XCTAssertEqual(settings.state, .init())
        settings.setCalmEnabled(true)
        settings.setThermalEnabled(true)
        XCTAssertEqual(settings.state.holds, [.calm, .thermal])
        let restored = CalmPlaybackSettings(defaults: defaults, center: center, thermalState: { .critical })
        XCTAssertEqual(restored.state.holds, [.thermal])
        restored.setThermalEnabled(false)
        XCTAssertTrue(restored.state.holds.isEmpty)
        XCTAssertFalse(defaults.bool(forKey: CalmPlaybackSettings.thermalEnabledKey))
    }

    @MainActor
    func testNotificationAndCoolingRefreshPublishIndependentHoldsWithoutDuplicates() throws {
        let suite = "CalmSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = NotificationCenter()
        var level = ProcessInfo.ThermalState.nominal, time = 0.0
        let settings = CalmPlaybackSettings(defaults: defaults, center: center, thermalState: { level }, now: { time })
        var states: [CalmPlaybackSettings.State] = []
        let binding = settings.$state.sink { states.append($0) }
        defer { binding.cancel() }
        settings.setThermalEnabled(true)
        settings.setCalmEnabled(true)
        level = .critical
        center.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        XCTAssertEqual(states.last?.holds, [.calm, .thermal])
        let count = states.count
        center.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        settings.setCalmEnabled(true)
        XCTAssertEqual(states.count, count)
        level = .fair
        center.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        time = 59
        settings.refreshThermalState()
        XCTAssertEqual(settings.state.holds, [.calm, .thermal])
        time = 60
        settings.refreshThermalState()
        XCTAssertEqual(states.last?.holds, [.calm])
        settings.toggleCalmMode()
        XCTAssertTrue(settings.state.holds.isEmpty)
    }
}
