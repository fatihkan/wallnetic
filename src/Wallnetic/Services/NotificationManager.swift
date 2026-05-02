import Foundation
import UserNotifications

/// Types of notifications the app can send
enum NotificationType: String, CaseIterable {
    case generationComplete = "Generation Complete"
    case scheduledWallpaper = "Scheduled Wallpaper"
    case generationError = "Generation Error"

    var description: String {
        switch self {
        case .generationComplete:
            return "When an AI wallpaper generation is complete"
        case .scheduledWallpaper:
            return "When a scheduled wallpaper is applied"
        case .generationError:
            return "When a generation error occurs"
        }
    }

    var icon: String {
        switch self {
        case .generationComplete: return "checkmark.circle.fill"
        case .scheduledWallpaper: return "clock.fill"
        case .generationError: return "exclamationmark.triangle.fill"
        }
    }
}

/// Manager for app notifications
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var notificationsEnabled: Bool {
        didSet {
            defaults.set(notificationsEnabled, forKey: "notificationsEnabled")
            if notificationsEnabled {
                requestAuthorization()
            }
        }
    }

    @Published var enabledNotifications: Set<NotificationType> {
        didSet {
            saveEnabledNotifications()
        }
    }

    @Published var isAuthorized = false
    @Published var soundEnabled: Bool {
        didSet {
            defaults.set(soundEnabled, forKey: "notificationSoundEnabled")
        }
    }

    private let defaults = UserDefaults.standard
    private let enabledKey = "enabledNotificationTypes"

    private init() {
        notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        soundEnabled = defaults.object(forKey: "notificationSoundEnabled") as? Bool ?? true

        // Load enabled notification types
        if let savedTypes = defaults.stringArray(forKey: enabledKey) {
            enabledNotifications = Set(savedTypes.compactMap { NotificationType(rawValue: $0) })
        } else {
            // Default: all enabled
            enabledNotifications = Set(NotificationType.allCases)
        }

        checkAuthorization()
    }

    // MARK: - Authorization

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.isAuthorized = granted
                if let error = error {
                    Log.notification.error("Authorization error: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func checkAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - Preferences

    func isEnabled(_ type: NotificationType) -> Bool {
        enabledNotifications.contains(type)
    }

    func setEnabled(_ type: NotificationType, enabled: Bool) {
        if enabled {
            enabledNotifications.insert(type)
        } else {
            enabledNotifications.remove(type)
        }
    }

    private func saveEnabledNotifications() {
        let typeStrings = enabledNotifications.map { $0.rawValue }
        defaults.set(typeStrings, forKey: enabledKey)
    }

    // MARK: - Send Notifications

    func sendNotification(type: NotificationType, title: String, body: String) {
        guard notificationsEnabled && isEnabled(type) else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        if soundEnabled {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Log.notification.error("Failed to send notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Convenience Methods

    func notifyGenerationComplete(styleName: String) {
        sendNotification(
            type: .generationComplete,
            title: "Wallpaper Ready",
            body: "Your \(styleName) wallpaper has been generated"
        )
    }

    func notifyScheduledWallpaper(styleName: String) {
        sendNotification(
            type: .scheduledWallpaper,
            title: "Daily Wallpaper Applied",
            body: "A new \(styleName) wallpaper is now active"
        )
    }

    func notifyGenerationError(message: String) {
        sendNotification(
            type: .generationError,
            title: "Generation Failed",
            body: message
        )
    }
}
