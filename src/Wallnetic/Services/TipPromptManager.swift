import Cocoa
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.wallnetic.app", category: "TipPrompt")

/// Decides when to offer the tip sheet without being asked (#337).
///
/// It is paced like the rating prompt, but more slowly, and it can always be
/// dismissed. ``TipPromptPolicy`` holds the gates:
///
///   • first ask after 14 days, 5 launches and 10 wallpaper applies,
///   • then at most once every 30 days; Not now snoozes for 30 days,
///   • nothing for 180 days after a tip,
///   • Don't ask again, or the Settings > About toggle, stops it for good,
///   • never in the session the rating prompt appeared in, nor within 7 days
///     of it.
///
/// The sheet attaches only to the key main window, after onboarding, and
/// never as a notification: App Review's Developer Code of Conduct rules out
/// manipulative purchase practices, and Apple services must not be used to
/// send unsolicited messages.
@MainActor
final class TipPromptManager {
    static let shared = TipPromptManager()

    // MARK: - UserDefaults keys

    private let firstSeenAtKey = "tipPrompt.firstSeenAt"
    private let lastAskedAtKey = "tipPrompt.lastAskedAt"
    private let snoozedUntilKey = "tipPrompt.snoozedUntil"
    private let lastTipAtKey = "tipPrompt.lastTipAt"

    private let defaults = UserDefaults.standard
    private var hasAskedThisSession = false
    private weak var presentedController: NSViewController?

    private init() {}

    // MARK: - Event recording

    /// Called once from AppDelegate on launch. Upgraded users start their
    /// first-ask wait on the first launch of a version with tips.
    func recordLaunch() {
        if defaults.object(forKey: firstSeenAtKey) == nil {
            defaults.set(Date(), forKey: firstSeenAtKey)
        }
    }

    /// Called by ``TipJar`` for every completed tip.
    func recordTip() {
        defaults.set(Date(), forKey: lastTipAtKey)
    }

    // MARK: - Presentation

    /// Called from AppDelegate's `NSWindow.didBecomeKeyNotification` observer,
    /// right after the rating prompt had its chance.
    func windowDidBecomeKey(_ window: NSWindow) {
        guard !hasAskedThisSession, presentedController == nil else { return }
        guard WindowManager.shared.mainWindow(in: [window]) != nil,
              RatingPromptManager.isPresentable(window),
              window.attachedSheet == nil,
              let host = window.contentViewController else { return }

        let rating = RatingPromptManager.shared
        let now = Date()
        guard TipPromptPolicy.shouldPrompt(
            now: now,
            firstSeenAt: defaults.object(forKey: firstSeenAtKey) as? Date ?? now,
            launchCount: rating.launchCount,
            cumulativeApplies: rating.cumulativeApplies,
            lastAskedAt: defaults.object(forKey: lastAskedAtKey) as? Date,
            snoozedUntil: defaults.object(forKey: snoozedUntilKey) as? Date,
            lastTipAt: defaults.object(forKey: lastTipAtKey) as? Date,
            remindersEnabled: defaults.object(forKey: TipPromptPolicy.remindersEnabledKey) as? Bool ?? true,
            ratingPromptedThisSession: rating.hasPromptedThisSession,
            lastRatingPromptAt: rating.lastPromptedAt,
            tipsAvailable: TipJar.shared.isAvailable
        ) else { return }

        hasAskedThisSession = true
        defaults.set(now, forKey: lastAskedAtKey)
        logger.info("Offering the tip sheet")

        let controller = NSHostingController(rootView: TipJarView(
            mode: .prompt,
            onNotNow: { [weak self] in self?.snooze() },
            onDontAskAgain: { [weak self] in self?.stopAsking() },
            onClose: { [weak self] in self?.dismissPrompt() }
        ))
        presentedController = controller
        host.presentAsSheet(controller)
    }

    private func snooze() {
        let until = Date().addingTimeInterval(Double(TipPromptPolicy.snoozeDays) * 86_400)
        defaults.set(until, forKey: snoozedUntilKey)
        dismissPrompt()
    }

    private func stopAsking() {
        defaults.set(false, forKey: TipPromptPolicy.remindersEnabledKey)
        dismissPrompt()
    }

    private func dismissPrompt() {
        guard let controller = presentedController else { return }
        controller.dismiss(nil)
        presentedController = nil
    }
}

/// The tip prompt's pacing, kept free of actor isolation so the gates can be
/// unit-tested and the Settings toggle can name the key.
enum TipPromptPolicy {
    /// Also bound to the Settings > About toggle.
    static let remindersEnabledKey = "tipPrompt.remindersEnabled"

    static let minDaysSinceFirstSeen = 14
    static let minLaunches = 5
    static let minApplies = 10
    static let minDaysBetweenAsks = 30
    static let snoozeDays = 30
    static let quietDaysAfterTip = 180
    static let minDaysAfterRatingPrompt = 7

    /// Whether every gate allows offering the tip sheet now. Pure, so the
    /// pacing can be unit-tested without UserDefaults, StoreKit or windows.
    static func shouldPrompt(
        now: Date,
        firstSeenAt: Date,
        launchCount: Int,
        cumulativeApplies: Int,
        lastAskedAt: Date?,
        snoozedUntil: Date?,
        lastTipAt: Date?,
        remindersEnabled: Bool,
        ratingPromptedThisSession: Bool,
        lastRatingPromptAt: Date?,
        tipsAvailable: Bool
    ) -> Bool {
        func daysSince(_ date: Date) -> Double { now.timeIntervalSince(date) / 86_400 }

        guard tipsAvailable, remindersEnabled else { return false }
        guard daysSince(firstSeenAt) >= Double(minDaysSinceFirstSeen),
              launchCount >= minLaunches,
              cumulativeApplies >= minApplies else { return false }
        if let lastAskedAt, daysSince(lastAskedAt) < Double(minDaysBetweenAsks) { return false }
        if let snoozedUntil, now < snoozedUntil { return false }
        if let lastTipAt, daysSince(lastTipAt) < Double(quietDaysAfterTip) { return false }
        guard !ratingPromptedThisSession else { return false }
        if let lastRatingPromptAt, daysSince(lastRatingPromptAt) < Double(minDaysAfterRatingPrompt) {
            return false
        }
        return true
    }
}
