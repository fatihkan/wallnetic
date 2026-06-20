import Foundation
import SwiftUI

/// Automatically switches wallpapers based on time of day
class TimeOfDayManager: ObservableObject {
    static let shared = TimeOfDayManager()

    enum TimeSlot: String, CaseIterable, Identifiable {
        case morning = "Morning"
        case afternoon = "Afternoon"
        case evening = "Evening"
        case night = "Night"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .morning: return "sunrise"
            case .afternoon: return "sun.max"
            case .evening: return "sunset"
            case .night: return "moon.stars"
            }
        }

        var defaultStartHour: Int {
            switch self {
            case .morning: return 6
            case .afternoon: return 12
            case .evening: return 17
            case .night: return 21
            }
        }

        var color: Color {
            switch self {
            case .morning: return .orange
            case .afternoon: return .yellow
            case .evening: return .pink
            case .night: return .indigo
            }
        }
    }

    // MARK: - Settings
    //
    // Backed by @Published + UserDefaults (not @AppStorage): @AppStorage inside
    // an ObservableObject does NOT fire objectWillChange, so the settings view
    // never re-rendered and the toggle's `.onChange` never fired — start() was
    // never called and time-of-day switching silently never ran. Same root
    // cause/fix as PlaylistManager (#226).

    @Published var isEnabled: Bool = UserDefaults.standard.bool(forKey: "tod.enabled") {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "tod.enabled") }
    }
    @Published var morningWallpaperPath: String = UserDefaults.standard.string(forKey: "tod.morningWallpaperPath") ?? "" {
        didSet { UserDefaults.standard.set(morningWallpaperPath, forKey: "tod.morningWallpaperPath") }
    }
    @Published var afternoonWallpaperPath: String = UserDefaults.standard.string(forKey: "tod.afternoonWallpaperPath") ?? "" {
        didSet { UserDefaults.standard.set(afternoonWallpaperPath, forKey: "tod.afternoonWallpaperPath") }
    }
    @Published var eveningWallpaperPath: String = UserDefaults.standard.string(forKey: "tod.eveningWallpaperPath") ?? "" {
        didSet { UserDefaults.standard.set(eveningWallpaperPath, forKey: "tod.eveningWallpaperPath") }
    }
    @Published var nightWallpaperPath: String = UserDefaults.standard.string(forKey: "tod.nightWallpaperPath") ?? "" {
        didSet { UserDefaults.standard.set(nightWallpaperPath, forKey: "tod.nightWallpaperPath") }
    }
    @Published var morningHour: Int = (UserDefaults.standard.object(forKey: "tod.morningHour") as? Int) ?? 6 {
        didSet { UserDefaults.standard.set(morningHour, forKey: "tod.morningHour") }
    }
    @Published var afternoonHour: Int = (UserDefaults.standard.object(forKey: "tod.afternoonHour") as? Int) ?? 12 {
        didSet { UserDefaults.standard.set(afternoonHour, forKey: "tod.afternoonHour") }
    }
    @Published var eveningHour: Int = (UserDefaults.standard.object(forKey: "tod.eveningHour") as? Int) ?? 17 {
        didSet { UserDefaults.standard.set(eveningHour, forKey: "tod.eveningHour") }
    }
    @Published var nightHour: Int = (UserDefaults.standard.object(forKey: "tod.nightHour") as? Int) ?? 21 {
        didSet { UserDefaults.standard.set(nightHour, forKey: "tod.nightHour") }
    }

    @Published var currentSlot: TimeSlot = .morning
    @Published var manualOverride = false

    private var timer: Timer?

    private init() {
        updateCurrentSlot()
        if isEnabled { start() }
    }

    // MARK: - Control

    func start() {
        isEnabled = true
        manualOverride = false
        updateCurrentSlot()
        applyCurrentSlot()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkAndSwitch()
        }
    }

    func stop() {
        isEnabled = false
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Slot Management

    func wallpaperPath(for slot: TimeSlot) -> String {
        switch slot {
        case .morning: return morningWallpaperPath
        case .afternoon: return afternoonWallpaperPath
        case .evening: return eveningWallpaperPath
        case .night: return nightWallpaperPath
        }
    }

    func setWallpaperPath(_ path: String, for slot: TimeSlot) {
        switch slot {
        case .morning: morningWallpaperPath = path
        case .afternoon: afternoonWallpaperPath = path
        case .evening: eveningWallpaperPath = path
        case .night: nightWallpaperPath = path
        }
    }

    func startHour(for slot: TimeSlot) -> Int {
        switch slot {
        case .morning: return morningHour
        case .afternoon: return afternoonHour
        case .evening: return eveningHour
        case .night: return nightHour
        }
    }

    func setStartHour(_ hour: Int, for slot: TimeSlot) {
        switch slot {
        case .morning: morningHour = hour
        case .afternoon: afternoonHour = hour
        case .evening: eveningHour = hour
        case .night: nightHour = hour
        }
    }

    // MARK: - Private

    private func checkAndSwitch() {
        guard isEnabled, !manualOverride else { return }

        let previousSlot = currentSlot
        updateCurrentSlot()

        if currentSlot != previousSlot {
            applyCurrentSlot()
        }
    }

    private func updateCurrentSlot() {
        let hour = Calendar.current.component(.hour, from: Date())

        if hour >= nightHour || hour < morningHour {
            currentSlot = .night
        } else if hour >= eveningHour {
            currentSlot = .evening
        } else if hour >= afternoonHour {
            currentSlot = .afternoon
        } else {
            currentSlot = .morning
        }
    }

    private func applyCurrentSlot() {
        let path = wallpaperPath(for: currentSlot)
        guard !path.isEmpty else { return }

        let url = URL(fileURLWithPath: path)
        if let wallpaper = WallpaperManager.shared.wallpapers.first(where: { $0.url.path == path }) {
            let slot = currentSlot.rawValue
            Log.timeOfDay.info("Switching to \(slot, privacy: .public) wallpaper: \(wallpaper.name, privacy: .public)")
            // Automatic switch — don't feed the rating prompt.
            WallpaperManager.shared.setWallpaper(wallpaper, userInitiated: false)
        }
    }

    /// Call when user manually changes wallpaper to pause auto-switch temporarily
    func onManualChange() {
        if isEnabled {
            manualOverride = true
            // Resume auto-switch after 30 minutes
            DispatchQueue.main.asyncAfter(deadline: .now() + 1800) { [weak self] in
                self?.manualOverride = false
            }
        }
    }
}
