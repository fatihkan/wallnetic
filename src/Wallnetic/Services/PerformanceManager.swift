import Foundation
import SwiftUI
import Combine

/// Performance mode settings for resource management
final class PerformanceManager: ObservableObject {
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
            case .quality: return "Metal: up to 60 frames per second for smoother motion."
            case .balanced: return "Metal: up to 30 frames per second for everyday playback."
            case .battery: return "Metal: up to 15 frames per second with less fluid motion."
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

    private let defaults: UserDefaults
    @Published var mode: PerformanceMode {
        didSet { defaults.set(mode.rawValue, forKey: "performance.mode") }
    }
    @AppStorage("performance.reducedAnimations") var reducedAnimations: Bool = false
    @AppStorage("performance.maxMemoryMB") var maxMemoryMB: Int = 512

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: "performance.mode")
        // Preserve the original display-name values and the old lowercase default.
        mode = PerformanceMode.allCases.first {
            $0.rawValue.caseInsensitiveCompare(saved ?? "") == .orderedSame
        } ?? .balanced
    }

    /// The controller owns one binding per display. New displays immediately
    /// receive the saved mode; updates never call play/pause or replace a player.
    func bind(to renderer: WallpaperRenderer) -> AnyCancellable {
        $mode.removeDuplicates().sink { [weak renderer] mode in
            renderer?.applyPerformanceMode(mode)
        }
    }
}
