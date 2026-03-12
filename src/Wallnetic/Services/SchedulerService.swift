import Foundation
import AppKit
import UserNotifications

/// Service for scheduling automatic wallpaper generation
class SchedulerService: ObservableObject {
    static let shared = SchedulerService()

    // MARK: - Published Properties

    @Published var isEnabled: Bool {
        didSet { saveSettings() }
    }

    @Published var scheduleHour: Int {
        didSet { saveSettings() }
    }

    @Published var scheduleMinute: Int {
        didSet { saveSettings() }
    }

    @Published var useRandomStyle: Bool {
        didSet { saveSettings() }
    }

    @Published var selectedStyleId: String {
        didSet { saveSettings() }
    }

    @Published var selectedProvider: AIProvider {
        didSet { saveSettings() }
    }

    @Published var lastGenerationDate: Date?
    @Published var isGenerating: Bool = false
    @Published var lastError: String?
    @Published var nextScheduledTime: Date?

    // MARK: - Private Properties

    private var timer: Timer?
    private let turkeyTimeZone = TimeZone(identifier: "Europe/Istanbul")!

    private let defaults = UserDefaults.standard
    private let enabledKey = "scheduler.isEnabled"
    private let hourKey = "scheduler.hour"
    private let minuteKey = "scheduler.minute"
    private let randomStyleKey = "scheduler.useRandomStyle"
    private let styleIdKey = "scheduler.styleId"
    private let providerKey = "scheduler.provider"
    private let lastGenKey = "scheduler.lastGenerationDate"

    // MARK: - Initialization

    private init() {
        // Load saved settings
        self.isEnabled = defaults.bool(forKey: enabledKey)
        self.scheduleHour = defaults.object(forKey: hourKey) as? Int ?? 9  // Default: 9 AM
        self.scheduleMinute = defaults.object(forKey: minuteKey) as? Int ?? 0
        self.useRandomStyle = defaults.object(forKey: randomStyleKey) as? Bool ?? true
        self.selectedStyleId = defaults.string(forKey: styleIdKey) ?? AIStyle.nature.id

        if let providerString = defaults.string(forKey: providerKey),
           let provider = AIProvider(rawValue: providerString) {
            self.selectedProvider = provider
        } else {
            self.selectedProvider = .replicate
        }

        if let lastGen = defaults.object(forKey: lastGenKey) as? Date {
            self.lastGenerationDate = lastGen
        }

        // Calculate next scheduled time
        updateNextScheduledTime()

        // Start timer if enabled
        if isEnabled {
            startTimer()
        }
    }

    // MARK: - Public Methods

    /// Start the scheduler
    func start() {
        isEnabled = true
        startTimer()
        updateNextScheduledTime()
    }

    /// Stop the scheduler
    func stop() {
        isEnabled = false
        stopTimer()
        nextScheduledTime = nil
    }

    /// Manually trigger generation (for testing)
    func triggerNow() {
        Task {
            await performScheduledGeneration()
        }
    }

    // MARK: - Timer Management

    private func startTimer() {
        stopTimer()

        // Check every 30 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkSchedule()
        }

        // Also check immediately
        checkSchedule()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func checkSchedule() {
        guard isEnabled else { return }

        let now = Date()
        let calendar = Calendar.current

        // Get current time in Turkey timezone
        var turkeyCalendar = calendar
        turkeyCalendar.timeZone = turkeyTimeZone

        let currentHour = turkeyCalendar.component(.hour, from: now)
        let currentMinute = turkeyCalendar.component(.minute, from: now)

        // Check if it's the scheduled time (within 1 minute window)
        if currentHour == scheduleHour && currentMinute == scheduleMinute {
            // Check if we already generated today
            if let lastGen = lastGenerationDate {
                let lastGenDay = turkeyCalendar.startOfDay(for: lastGen)
                let today = turkeyCalendar.startOfDay(for: now)

                if lastGenDay >= today {
                    // Already generated today
                    return
                }
            }

            // Time to generate!
            Task {
                await performScheduledGeneration()
            }
        }

        // Update next scheduled time
        updateNextScheduledTime()
    }

    private func updateNextScheduledTime() {
        guard isEnabled else {
            nextScheduledTime = nil
            return
        }

        let now = Date()
        var turkeyCalendar = Calendar.current
        turkeyCalendar.timeZone = turkeyTimeZone

        // Create date components for scheduled time
        var components = turkeyCalendar.dateComponents([.year, .month, .day], from: now)
        components.hour = scheduleHour
        components.minute = scheduleMinute
        components.second = 0

        guard var scheduledDate = turkeyCalendar.date(from: components) else {
            nextScheduledTime = nil
            return
        }

        // If scheduled time has passed today, move to tomorrow
        if scheduledDate <= now {
            scheduledDate = turkeyCalendar.date(byAdding: .day, value: 1, to: scheduledDate) ?? scheduledDate
        }

        nextScheduledTime = scheduledDate
    }

    // MARK: - Generation

    @MainActor
    private func performScheduledGeneration() async {
        guard !isGenerating else { return }

        isGenerating = true
        lastError = nil

        // Select style
        let style: AIStyle
        if useRandomStyle {
            style = AIStyle.allStyles.randomElement() ?? .nature
        } else {
            style = AIStyle.allStyles.first { $0.id == selectedStyleId } ?? .nature
        }

        // Get screen resolution
        let resolution = AIService.screenResolution

        // Create request
        let request = GenerationRequest(
            prompt: "beautiful wallpaper, high quality, stunning",
            style: style,
            width: resolution.width,
            height: resolution.height
        )

        do {
            // Check if API key is available
            guard KeychainManager.shared.getAPIKey(for: selectedProvider) != nil else {
                throw AIServiceError.noAPIKey
            }

            // Generate image
            let result = try await AIService.shared.generateImage(
                request: request,
                provider: selectedProvider
            )

            // Set as wallpaper
            if let localURL = result.localURL {
                try await setAsWallpaper(localURL)
            }

            // Save to history
            if let localURL = result.localURL,
               let imageData = try? Data(contentsOf: localURL),
               let image = NSImage(data: imageData) {
                GenerationHistoryManager.shared.addGeneration(
                    image: image,
                    prompt: "Scheduled generation",
                    style: style,
                    provider: selectedProvider,
                    width: request.width,
                    height: request.height
                )
            }

            // Update last generation date
            lastGenerationDate = Date()
            defaults.set(lastGenerationDate, forKey: lastGenKey)

            // Show notification
            showNotification(
                title: "Wallpaper Updated",
                body: "New \(style.name) wallpaper has been set!"
            )

            // Update next scheduled time
            updateNextScheduledTime()

        } catch {
            lastError = error.localizedDescription
            showNotification(
                title: "Wallpaper Generation Failed",
                body: error.localizedDescription
            )
        }

        isGenerating = false
    }

    private func setAsWallpaper(_ url: URL) async throws {
        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    }

    // MARK: - Notifications

    private func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Request notification permissions
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    // MARK: - Persistence

    private func saveSettings() {
        defaults.set(isEnabled, forKey: enabledKey)
        defaults.set(scheduleHour, forKey: hourKey)
        defaults.set(scheduleMinute, forKey: minuteKey)
        defaults.set(useRandomStyle, forKey: randomStyleKey)
        defaults.set(selectedStyleId, forKey: styleIdKey)
        defaults.set(selectedProvider.rawValue, forKey: providerKey)

        // Restart timer if needed
        if isEnabled {
            startTimer()
        } else {
            stopTimer()
        }

        updateNextScheduledTime()
    }

    // MARK: - Formatted Time

    /// Get formatted schedule time in Turkey timezone
    var formattedScheduleTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = turkeyTimeZone

        var components = DateComponents()
        components.hour = scheduleHour
        components.minute = scheduleMinute

        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(String(format: "%02d", scheduleHour)):\(String(format: "%02d", scheduleMinute))"
    }

    /// Get formatted next scheduled time
    var formattedNextScheduledTime: String? {
        guard let next = nextScheduledTime else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM HH:mm"
        formatter.timeZone = turkeyTimeZone
        formatter.locale = Locale(identifier: "tr_TR")

        return formatter.string(from: next)
    }
}
