import Foundation
import AppKit
import UserNotifications

/// Service for scheduling automatic video wallpaper generation
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

    @Published var useRandomModel: Bool {
        didSet { saveSettings() }
    }

    @Published var selectedModel: VideoModel {
        didSet { saveSettings() }
    }

    @Published var videoDuration: Int {
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
    private let randomModelKey = "scheduler.useRandomModel"
    private let modelKey = "scheduler.videoModel"
    private let durationKey = "scheduler.videoDuration"
    private let lastGenKey = "scheduler.lastGenerationDate"

    // Anime-optimized prompts for scheduled generation
    private let animePrompts = [
        "beautiful anime landscape, cherry blossoms falling, soft pink sky, studio ghibli style, looping animation",
        "anime night city skyline, neon lights reflecting on water, cyberpunk aesthetic, seamless loop",
        "peaceful anime forest scene, fireflies floating, magical atmosphere, gentle wind, loop",
        "anime ocean waves at sunset, golden hour lighting, calm and serene, perfect loop",
        "cozy anime room interior, rain on window, warm lighting, lo-fi aesthetic, seamless loop",
        "anime mountain scenery, clouds moving slowly, peaceful meditation scene, loop animation",
        "anime starry night sky, shooting stars, northern lights, cosmic atmosphere, looping",
        "anime sakura tree in wind, petals floating, spring scene, tranquil mood, seamless loop"
    ]

    // MARK: - Initialization

    private init() {
        // Load saved settings
        self.isEnabled = defaults.bool(forKey: enabledKey)
        self.scheduleHour = defaults.object(forKey: hourKey) as? Int ?? 9  // Default: 9 AM
        self.scheduleMinute = defaults.object(forKey: minuteKey) as? Int ?? 0
        self.useRandomModel = defaults.object(forKey: randomModelKey) as? Bool ?? true
        self.videoDuration = defaults.object(forKey: durationKey) as? Int ?? 5

        if let modelString = defaults.string(forKey: modelKey),
           let model = VideoModel(rawValue: modelString) {
            self.selectedModel = model
        } else {
            self.selectedModel = .klingStandard
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

        // Select model
        let model: VideoModel
        if useRandomModel {
            // Prefer anime-optimized models for scheduled generation
            let animeModels: [VideoModel] = [.klingStandard, .klingPro, .minimax, .pika]
            model = animeModels.randomElement() ?? .klingStandard
        } else {
            model = selectedModel
        }

        // Select random anime prompt
        let prompt = animePrompts.randomElement() ?? animePrompts[0]

        // Create video request
        let request = VideoGenerationRequest(
            prompt: prompt,
            negativePrompt: "blurry, low quality, static, no motion, distorted",
            model: model,
            duration: min(videoDuration, model.maxDuration),
            aspectRatio: "16:9",
            sourceImage: nil
        )

        do {
            // Check if API key is available
            guard KeychainManager.shared.getAPIKey(for: .falai) != nil else {
                throw AIServiceError.noAPIKey
            }

            // Generate video
            let result = try await AIService.shared.generateVideo(request: request)

            // Import to wallpaper library
            _ = try await WallpaperManager.shared.importVideo(from: result.localURL)

            // Save to history
            GenerationHistoryManager.shared.addGeneration(from: result, aspectRatio: "16:9")

            // Update last generation date
            lastGenerationDate = Date()
            defaults.set(lastGenerationDate, forKey: lastGenKey)

            // Show notification
            showNotification(
                title: "Video Wallpaper Ready",
                body: "New \(model.displayName) wallpaper has been generated!"
            )

            // Update next scheduled time
            updateNextScheduledTime()

        } catch {
            lastError = error.localizedDescription
            showNotification(
                title: "Video Generation Failed",
                body: error.localizedDescription
            )
        }

        isGenerating = false
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
        defaults.set(useRandomModel, forKey: randomModelKey)
        defaults.set(selectedModel.rawValue, forKey: modelKey)
        defaults.set(videoDuration, forKey: durationKey)

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
        formatter.locale = Locale.current

        return formatter.string(from: next)
    }
}
