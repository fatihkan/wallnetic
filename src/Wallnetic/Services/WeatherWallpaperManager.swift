import Foundation
import CoreLocation
import SwiftUI

/// Changes wallpaper based on current weather conditions
class WeatherWallpaperManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherWallpaperManager()

    enum WeatherCondition: String, CaseIterable, Identifiable {
        case sunny = "Sunny"
        case cloudy = "Cloudy"
        case rainy = "Rainy"
        case snowy = "Snowy"
        case stormy = "Stormy"
        case night = "Night"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .sunny: return "sun.max.fill"
            case .cloudy: return "cloud.fill"
            case .rainy: return "cloud.rain.fill"
            case .snowy: return "cloud.snow.fill"
            case .stormy: return "cloud.bolt.fill"
            case .night: return "moon.stars.fill"
            }
        }

        var color: Color {
            switch self {
            case .sunny: return .yellow
            case .cloudy: return .gray
            case .rainy: return .blue
            case .snowy: return .cyan
            case .stormy: return .purple
            case .night: return .indigo
            }
        }
    }

    // MARK: - Settings

    @AppStorage("weather.enabled") var isEnabled: Bool = false
    @AppStorage("weather.sunnyPath") var sunnyPath: String = ""
    @AppStorage("weather.cloudyPath") var cloudyPath: String = ""
    @AppStorage("weather.rainyPath") var rainyPath: String = ""
    @AppStorage("weather.snowyPath") var snowyPath: String = ""
    @AppStorage("weather.stormyPath") var stormyPath: String = ""
    @AppStorage("weather.nightPath") var nightPath: String = ""
    @AppStorage("weather.city") var manualCity: String = ""

    @Published var currentCondition: WeatherCondition = .sunny
    @Published var locationStatus: String = "Not started"
    @Published var lastUpdate: Date?

    private let locationManager = CLLocationManager()
    private var timer: Timer?

    private override init() {
        super.init()
        locationManager.delegate = self
        if isEnabled { start() }
    }

    // MARK: - Control

    func start() {
        isEnabled = true
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        fetchWeather()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            self?.fetchWeather()
        }
    }

    func stop() {
        isEnabled = false
        locationManager.stopUpdatingLocation()
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Wallpaper Path

    func wallpaperPath(for condition: WeatherCondition) -> String {
        switch condition {
        case .sunny: return sunnyPath
        case .cloudy: return cloudyPath
        case .rainy: return rainyPath
        case .snowy: return snowyPath
        case .stormy: return stormyPath
        case .night: return nightPath
        }
    }

    func setWallpaperPath(_ path: String, for condition: WeatherCondition) {
        switch condition {
        case .sunny: sunnyPath = path
        case .cloudy: cloudyPath = path
        case .rainy: rainyPath = path
        case .snowy: snowyPath = path
        case .stormy: stormyPath = path
        case .night: nightPath = path
        }
    }

    // MARK: - Weather Fetching

    private func fetchWeather() {
        // Use simple heuristic based on time if no API configured
        // In production, integrate WeatherKit or OpenWeatherMap
        let hour = Calendar.current.component(.hour, from: Date())

        if hour >= 21 || hour < 6 {
            updateCondition(.night)
        } else {
            // Simulated - replace with real API call
            updateCondition(.sunny)
        }

        locationStatus = "Updated"
        lastUpdate = Date()
    }

    private func updateCondition(_ condition: WeatherCondition) {
        guard condition != currentCondition else { return }

        currentCondition = condition
        let path = wallpaperPath(for: condition)
        guard !path.isEmpty else { return }

        if let wallpaper = WallpaperManager.shared.wallpapers.first(where: { $0.url.path == path }) {
            NSLog("[Weather] Condition: %@ -> wallpaper: %@", condition.rawValue, wallpaper.name)
            WallpaperManager.shared.setWallpaper(wallpaper)
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Location available - could use for weather API
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationStatus = "Location unavailable"
    }
}
