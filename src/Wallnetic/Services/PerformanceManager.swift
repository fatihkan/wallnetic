import Foundation
import SwiftUI

/// Performance mode settings for resource management
class PerformanceManager: ObservableObject {
    static let shared = PerformanceManager()

    enum PerformanceMode: String, CaseIterable {
        case quality = "Quality"
        case balanced = "Balanced"
        case battery = "Battery Saver"

        var icon: String {
            switch self {
            case .quality: return "sparkles"
            case .balanced: return "speedometer"
            case .battery: return "battery.75percent"
            }
        }

        var description: String {
            switch self {
            case .quality: return "Maximum quality, higher resource usage"
            case .balanced: return "Good balance of quality and performance"
            case .battery: return "Minimal resource usage, reduced quality"
            }
        }

        var maxFPS: Int {
            switch self {
            case .quality: return 60
            case .balanced: return 30
            case .battery: return 15
            }
        }

        var thumbnailQuality: CGFloat {
            switch self {
            case .quality: return 0.9
            case .balanced: return 0.7
            case .battery: return 0.5
            }
        }
    }

    @AppStorage("performance.mode") private var modeRaw: String = "balanced"
    @AppStorage("performance.reducedAnimations") var reducedAnimations: Bool = false
    @AppStorage("performance.maxMemoryMB") var maxMemoryMB: Int = 512

    var mode: PerformanceMode {
        get { PerformanceMode(rawValue: modeRaw) ?? .balanced }
        set { modeRaw = newValue.rawValue; objectWillChange.send() }
    }

    private init() {}
}
