import Foundation
import SwiftUI

/// Lightweight privacy-first analytics
/// Uses TelemetryDeck-compatible event format (no PII collected)
class AnalyticsManager {
    static let shared = AnalyticsManager()

    @AppStorage("analytics.enabled") private var isEnabled: Bool = true
    private let appID: String? = nil  // Set TelemetryDeck App ID here

    private init() {}

    /// Track an event
    func track(_ event: String, properties: [String: String] = [:]) {
        guard isEnabled, appID != nil else { return }

        // In production, send to TelemetryDeck API
        // For now, log locally
        #if DEBUG
        NSLog("[Analytics] %@ %@", event, properties.description)
        #endif
    }

    // MARK: - Standard Events

    func trackAppLaunch() { track("app.launch") }
    func trackWallpaperSet(name: String) { track("wallpaper.set", properties: ["name": name]) }
    func trackImport(format: String) { track("wallpaper.import", properties: ["format": format]) }
    func trackEffectApplied(preset: String) { track("effect.applied", properties: ["preset": preset]) }
    func trackFeatureUsed(_ feature: String) { track("feature.used", properties: ["feature": feature]) }
}
