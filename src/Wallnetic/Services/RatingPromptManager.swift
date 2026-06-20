import Cocoa
import StoreKit
import os.log

private let logger = Logger(subsystem: "com.wallnetic.app", category: "RatingPrompt")

/// Decides when to surface the App Store rating prompt (Wave 1, v1.4).
///
/// Wallnetic shipped with zero App Store reviews while competitors carry
/// tens of thousands, so the goal is simply to ask happy users at a good
/// moment. The heuristic asks only after several positive sessions:
///
///   • never on first launch (needs ``minLaunches`` launches),
///   • never on the automatic launch restore (needs the *second* deliberate
///     apply of a session — the first apply is `restoreLastWallpaper()`),
///   • after enough cumulative successful applies (``minApplies``),
///   • at most once per app version.
///
/// `AppStore.requestReview(in:)` layers its own annual cap on top (max three
/// prompts per 365 days, and it may choose not to show at all), so these
/// gates only decide *when we are allowed to ask* — the system has the final
/// say. The call is `@MainActor`-isolated and needs a presenting
/// `NSViewController`; in this menu-bar/accessory app the prompt fires right
/// after a deliberate in-app wallpaper change, so a window is normally
/// available. If none is, we skip without consuming the per-version slot.
final class RatingPromptManager {
    static let shared = RatingPromptManager()

    /// App Store listing for the explicit "Rate Wallnetic" action.
    /// Source: App Store product page id6760347328.
    static let appStoreID = "6760347328"
    static let writeReviewURL = URL(
        string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review"
    )!

    // MARK: - UserDefaults keys

    private let launchCountKey = "ratingPrompt.launchCount"
    private let applyCountKey = "ratingPrompt.applyCount"
    private let lastPromptedVersionKey = "ratingPrompt.lastPromptedVersion"

    private let defaults = UserDefaults.standard

    // MARK: - Thresholds

    static let minLaunches = 3
    static let minApplies = 5

    // MARK: - Session state (reset on relaunch)

    private var appliesThisSession = 0
    private var hasPromptedThisSession = false

    private init() {}

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    // MARK: - Event recording

    /// Called once from AppDelegate on launch.
    func recordLaunch() {
        defaults.set(defaults.integer(forKey: launchCountKey) + 1, forKey: launchCountKey)
    }

    /// Called from `WallpaperManager` whenever a wallpaper is successfully
    /// applied (the meaningful positive moment for a wallpaper app).
    func recordWallpaperApplied() {
        appliesThisSession += 1
        defaults.set(defaults.integer(forKey: applyCountKey) + 1, forKey: applyCountKey)
        requestReviewIfAppropriate()
    }

    // MARK: - Manual entry (Settings → About → "Rate Wallnetic")

    /// Explicit, user-initiated rating. Opens the App Store write-review page
    /// directly — the in-app review sheet is reserved for the automatic prompt
    /// and is not guaranteed to appear, which is the wrong behaviour for a
    /// button the user deliberately tapped.
    func openWriteReviewPage() {
        NSWorkspace.shared.open(Self.writeReviewURL)
    }

    // MARK: - Gating (pure, unit-testable)

    /// Whether the maturity gates allow asking for a review right now. Kept
    /// pure (no UserDefaults / NSApp) so the heuristic can be unit-tested.
    ///
    /// - `appliesThisSession >= 2` skips the automatic launch restore (the
    ///   session's first apply) and waits for a deliberate change.
    /// - `lastPromptedVersion != currentVersion` asks at most once per app
    ///   version so updates can re-engage without nagging within a release.
    static func shouldPrompt(
        launchCount: Int,
        cumulativeApplies: Int,
        appliesThisSession: Int,
        lastPromptedVersion: String?,
        currentVersion: String
    ) -> Bool {
        guard appliesThisSession >= 2 else { return false }
        guard launchCount >= minLaunches else { return false }
        guard cumulativeApplies >= minApplies else { return false }
        guard lastPromptedVersion != currentVersion else { return false }
        return true
    }

    // MARK: - Private

    private func requestReviewIfAppropriate() {
        guard !hasPromptedThisSession else { return }
        guard Self.shouldPrompt(
            launchCount: defaults.integer(forKey: launchCountKey),
            cumulativeApplies: defaults.integer(forKey: applyCountKey),
            appliesThisSession: appliesThisSession,
            lastPromptedVersion: defaults.string(forKey: lastPromptedVersionKey),
            currentVersion: currentVersion
        ) else { return }

        Task { @MainActor [weak self] in
            guard let self, !self.hasPromptedThisSession else { return }
            guard let controller = self.presentationController else { return }
            self.hasPromptedThisSession = true
            self.defaults.set(self.currentVersion, forKey: self.lastPromptedVersionKey)
            logger.info("Requesting App Store review (version \(self.currentVersion, privacy: .public))")
            AppStore.requestReview(in: controller)
        }
    }

    /// A view controller to present the rating sheet from. Prefers the focused
    /// window, then the main window, then any visible window.
    @MainActor
    private var presentationController: NSViewController? {
        let window = NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.windows.first(where: { $0.isVisible })
        return window?.contentViewController
    }
}
