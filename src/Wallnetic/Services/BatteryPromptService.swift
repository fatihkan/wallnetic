import Cocoa
import os.log

private let logger = Logger(subsystem: "com.wallnetic.app", category: "BatteryPrompt")

/// Presents the battery-mode prompt (#172) and tracks per-session / persistent
/// overrides so the user can choose to keep the live wallpaper running on
/// battery power.
final class BatteryPromptService {
    static let shared = BatteryPromptService()

    // MARK: - UserDefaults keys

    private let promptEnabledKey = "batteryPromptEnabled"
    private let defaultChoiceKey = "batteryPromptDefaultChoice"  // "pause" | "continue"
    /// Exposed in Settings. When true, bypasses the battery pause entirely.
    static let alwaysPlayKey = "alwaysPlayOnBattery"

    private let defaults = UserDefaults.standard

    // MARK: - Session state (reset on relaunch)

    private(set) var hasAskedThisSession = false
    private(set) var sessionContinueOnBattery = false

    enum Trigger { case launch, runtime }

    private init() {}

    // MARK: - Persistent preferences

    var isPromptEnabled: Bool {
        defaults.object(forKey: promptEnabledKey) as? Bool ?? true
    }

    var savedDefaultChoice: String? {
        defaults.string(forKey: defaultChoiceKey)
    }

    var alwaysPlayOnBattery: Bool {
        get { defaults.bool(forKey: Self.alwaysPlayKey) }
        set { defaults.set(newValue, forKey: Self.alwaysPlayKey) }
    }

    func resetPreferences() {
        defaults.removeObject(forKey: promptEnabledKey)
        defaults.removeObject(forKey: defaultChoiceKey)
        defaults.removeObject(forKey: Self.alwaysPlayKey)
        hasAskedThisSession = false
        sessionContinueOnBattery = false
    }

    // MARK: - Effective state (consumed by PowerManager)

    /// Should playback be paused on battery, factoring in session and
    /// persistent overrides? Returns false when the user has opted to keep
    /// the wallpaper running on battery.
    var effectivePauseOnBattery: Bool {
        if alwaysPlayOnBattery { return false }
        if sessionContinueOnBattery { return false }
        if savedDefaultChoice == "continue" { return false }
        return WallpaperManager.shared.pauseOnBattery
    }

    // MARK: - Prompt triggers

    /// Called from AppDelegate on launch. If we're already on battery and the
    /// user hasn't silenced the prompt, show the alert.
    func checkOnLaunch() {
        guard PowerManager.shared.isOnBattery else { return }
        guard WallpaperManager.shared.pauseOnBattery else { return }
        askIfNeeded(trigger: .launch)
    }

    /// Called by PowerManager when the power source flips from AC to battery.
    func onSwitchedToBattery() {
        guard WallpaperManager.shared.pauseOnBattery else { return }
        askIfNeeded(trigger: .runtime)
    }

    // MARK: - Private

    private func askIfNeeded(trigger: Trigger) {
        guard !hasAskedThisSession else { return }

        // User flipped the Settings toggle — no prompt, silently continue.
        if alwaysPlayOnBattery {
            hasAskedThisSession = true
            applyChoice("continue")
            return
        }

        if !isPromptEnabled, let choice = savedDefaultChoice {
            logger.info("Applying saved battery choice silently: \(choice)")
            hasAskedThisSession = true
            applyChoice(choice)
            return
        }

        hasAskedThisSession = true

        DispatchQueue.main.async { [weak self] in
            self?.showAlert(trigger: trigger)
        }
    }

    private func showAlert(trigger: Trigger) {
        let alert = NSAlert()
        alert.messageText = "Pil modunda çalışıyor"
        alert.informativeText = trigger == .launch
            ? "Wallnetic pil ömrünü korumak için canlı duvar kağıdını duraklattı. Oynatmaya devam etmek ister misiniz?"
            : "Şarj kablosu çıkarıldı. Pil ömrünü korumak için canlı duvar kağıdı duraklatıldı. Oynatmaya devam etmek ister misiniz?"
        alert.alertStyle = .informational

        alert.addButton(withTitle: "Canlı devam et")
        alert.addButton(withTitle: "Pil koruyucu (duraklat)")

        let rememberCheckbox = NSButton(
            checkboxWithTitle: "Bir daha sorma",
            target: nil,
            action: nil
        )
        rememberCheckbox.state = .off
        alert.accessoryView = rememberCheckbox

        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()
        let choice: String = (response == .alertFirstButtonReturn) ? "continue" : "pause"

        if rememberCheckbox.state == .on {
            defaults.set(choice, forKey: defaultChoiceKey)
            defaults.set(false, forKey: promptEnabledKey)
            // Sync the Settings toggle so the user can see/change it later.
            if choice == "continue" {
                defaults.set(true, forKey: Self.alwaysPlayKey)
            }
            logger.info("User saved battery preference: \(choice)")
        }

        logger.info("User chose battery action: \(choice)")
        applyChoice(choice)
    }

    private func applyChoice(_ choice: String) {
        guard choice == "continue" else { return }
        sessionContinueOnBattery = true

        DispatchQueue.main.async {
            WallpaperManager.shared.isPlaying = true
            if let delegate = WallpaperManager.shared.playbackDelegate {
                delegate.playbackPlay()
            } else {
                NotificationCenter.default.post(name: .playbackStateDidChange, object: true)
            }
        }
    }
}
