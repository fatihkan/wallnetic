import XCTest
@testable import Wallnetic

final class TipPromptPolicyTests: XCTestCase {

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func daysAgo(_ days: Int) -> Date {
        now.addingTimeInterval(-Double(days) * 86_400)
    }

    /// Every gate satisfied unless a test overrides it.
    private func shouldPrompt(
        firstSeenAt: Date? = nil,
        launchCount: Int = TipPromptPolicy.minLaunches,
        cumulativeApplies: Int = TipPromptPolicy.minApplies,
        lastAskedAt: Date? = nil,
        snoozedUntil: Date? = nil,
        lastTipAt: Date? = nil,
        remindersEnabled: Bool = true,
        ratingPromptedThisSession: Bool = false,
        lastRatingPromptAt: Date? = nil,
        tipsAvailable: Bool = true
    ) -> Bool {
        TipPromptPolicy.shouldPrompt(
            now: now,
            firstSeenAt: firstSeenAt ?? daysAgo(TipPromptPolicy.minDaysSinceFirstSeen),
            launchCount: launchCount,
            cumulativeApplies: cumulativeApplies,
            lastAskedAt: lastAskedAt,
            snoozedUntil: snoozedUntil,
            lastTipAt: lastTipAt,
            remindersEnabled: remindersEnabled,
            ratingPromptedThisSession: ratingPromptedThisSession,
            lastRatingPromptAt: lastRatingPromptAt,
            tipsAvailable: tipsAvailable
        )
    }

    // MARK: - First ask

    func testPromptsWhenAllGatesAreMet() {
        XCTAssertTrue(shouldPrompt())
    }

    func testDoesNotPromptBeforeMinDays() {
        XCTAssertFalse(shouldPrompt(firstSeenAt: daysAgo(TipPromptPolicy.minDaysSinceFirstSeen - 1)))
    }

    func testDoesNotPromptBeforeMinLaunches() {
        XCTAssertFalse(shouldPrompt(launchCount: TipPromptPolicy.minLaunches - 1))
    }

    func testDoesNotPromptBeforeMinApplies() {
        XCTAssertFalse(shouldPrompt(cumulativeApplies: TipPromptPolicy.minApplies - 1))
    }

    // MARK: - Availability and opt-out

    func testDoesNotPromptWithoutTipProducts() {
        // The direct-download build gets no products from the App Store.
        XCTAssertFalse(shouldPrompt(tipsAvailable: false))
    }

    func testDoesNotPromptAfterDontAskAgain() {
        XCTAssertFalse(shouldPrompt(remindersEnabled: false))
    }

    // MARK: - Pacing

    func testDoesNotPromptWithinIntervalOfLastAsk() {
        XCTAssertFalse(shouldPrompt(lastAskedAt: daysAgo(TipPromptPolicy.minDaysBetweenAsks - 1)))
    }

    func testPromptsAgainAfterInterval() {
        XCTAssertTrue(shouldPrompt(lastAskedAt: daysAgo(TipPromptPolicy.minDaysBetweenAsks)))
    }

    func testDoesNotPromptWhileSnoozed() {
        XCTAssertFalse(shouldPrompt(snoozedUntil: now.addingTimeInterval(60)))
    }

    func testPromptsOnceSnoozeEnds() {
        XCTAssertTrue(shouldPrompt(snoozedUntil: now))
    }

    func testStaysQuietAfterATip() {
        XCTAssertFalse(shouldPrompt(lastTipAt: daysAgo(TipPromptPolicy.quietDaysAfterTip - 1)))
    }

    func testPromptsAgainLongAfterATip() {
        XCTAssertTrue(shouldPrompt(lastTipAt: daysAgo(TipPromptPolicy.quietDaysAfterTip)))
    }

    // MARK: - Distance from the rating prompt

    func testDoesNotPromptInTheRatingPromptSession() {
        XCTAssertFalse(shouldPrompt(ratingPromptedThisSession: true))
    }

    func testDoesNotPromptSoonAfterRatingPrompt() {
        XCTAssertFalse(shouldPrompt(lastRatingPromptAt: daysAgo(TipPromptPolicy.minDaysAfterRatingPrompt - 1)))
    }

    func testPromptsWellAfterRatingPrompt() {
        XCTAssertTrue(shouldPrompt(lastRatingPromptAt: daysAgo(TipPromptPolicy.minDaysAfterRatingPrompt)))
    }
}
