import Foundation
import Combine

/// The saved playback rules (#350). Main-thread only.
final class PlaybackRulesSettings: ObservableObject {
    static let shared = PlaybackRulesSettings()
    static let storageKey = "playback.rules.v1"

    @Published private(set) var rules: PlaybackRulesConfiguration
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(PlaybackRulesConfiguration.self, from: data) {
            rules = saved
        } else {
            rules = PlaybackRulesConfiguration()
        }
    }

    func update(_ change: (inout PlaybackRulesConfiguration) -> Void) {
        var next = rules
        change(&next)
        guard next != rules else { return }
        if let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: Self.storageKey)
        }
        rules = next
    }

    /// Adds apps to a rule's list, skipping ones it already has.
    static func adding(_ apps: [PlaybackRuleApp], to list: [PlaybackRuleApp]) -> [PlaybackRuleApp] {
        var result = list
        for app in apps where !result.contains(where: { $0.bundleID == app.bundleID }) {
            result.append(app)
        }
        return result
    }
}
