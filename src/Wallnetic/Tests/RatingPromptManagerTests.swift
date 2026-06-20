import XCTest
@testable import Wallnetic

final class RatingPromptManagerTests: XCTestCase {

    private let version = "1.4"

    // MARK: - Skip the automatic launch restore

    func testDoesNotPromptOnFirstApplyOfSession() {
        // appliesThisSession == 1 is the launch restore, never a prompt moment,
        // even when every cumulative threshold is already satisfied.
        XCTAssertFalse(RatingPromptManager.shouldPrompt(
            launchCount: 99,
            cumulativeApplies: 99,
            appliesThisSession: 1,
            lastPromptedVersion: nil,
            currentVersion: version
        ))
    }

    // MARK: - Maturity thresholds

    func testDoesNotPromptBeforeMinLaunches() {
        XCTAssertFalse(RatingPromptManager.shouldPrompt(
            launchCount: RatingPromptManager.minLaunches - 1,
            cumulativeApplies: RatingPromptManager.minApplies,
            appliesThisSession: 2,
            lastPromptedVersion: nil,
            currentVersion: version
        ))
    }

    func testDoesNotPromptBeforeMinApplies() {
        XCTAssertFalse(RatingPromptManager.shouldPrompt(
            launchCount: RatingPromptManager.minLaunches,
            cumulativeApplies: RatingPromptManager.minApplies - 1,
            appliesThisSession: 2,
            lastPromptedVersion: nil,
            currentVersion: version
        ))
    }

    func testPromptsWhenAllGatesAreMet() {
        XCTAssertTrue(RatingPromptManager.shouldPrompt(
            launchCount: RatingPromptManager.minLaunches,
            cumulativeApplies: RatingPromptManager.minApplies,
            appliesThisSession: 2,
            lastPromptedVersion: nil,
            currentVersion: version
        ))
    }

    // MARK: - Once per app version

    func testDoesNotPromptTwiceForSameVersion() {
        XCTAssertFalse(RatingPromptManager.shouldPrompt(
            launchCount: RatingPromptManager.minLaunches,
            cumulativeApplies: RatingPromptManager.minApplies,
            appliesThisSession: 2,
            lastPromptedVersion: version,
            currentVersion: version
        ))
    }

    func testPromptsAgainAfterVersionBump() {
        XCTAssertTrue(RatingPromptManager.shouldPrompt(
            launchCount: RatingPromptManager.minLaunches,
            cumulativeApplies: RatingPromptManager.minApplies,
            appliesThisSession: 2,
            lastPromptedVersion: "1.3.1",
            currentVersion: version
        ))
    }
}
