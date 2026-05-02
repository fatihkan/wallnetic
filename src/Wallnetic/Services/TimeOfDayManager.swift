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

    @AppStorage("tod.enabled") var isEnabled: Bool = false
    @AppStorage("tod.morningWallpaperPath") var morningWallpaperPath: String = ""
    @AppStorage("tod.afternoonWallpaperPath") var afternoonWallpaperPath: String = ""
    @AppStorage("tod.eveningWallpaperPath") var eveningWallpaperPath: String = ""
    @AppStorage("tod.nightWallpaperPath") var nightWallpaperPath: String = ""
    @AppStorage("tod.morningHour") var morningHour: Int = 6
    @AppStorage("tod.afternoonHour") var afternoonHour: Int = 12
    @AppStorage("tod.eveningHour") var eveningHour: Int = 17
    @AppStorage("tod.nightHour") var nightHour: Int = 21

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
            WallpaperManager.shared.setWallpaper(wallpaper)
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
