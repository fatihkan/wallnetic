import AppKit
import Foundation

/// The interface languages Wallnetic can be switched to (#351).
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case german = "de"
    case french = "fr"
    case japanese = "ja"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    /// "System Default", or the language's own name. A language's own name
    /// reads the same in every interface language, so it is not translated.
    var title: String {
        switch self {
        case .system: return String(localized: "System Default")
        case .english: return "English" // l10n:ignore
        case .german: return "Deutsch" // l10n:ignore
        case .french: return "Français"
        case .japanese: return "日本語"
        case .simplifiedChinese: return "简体中文"
        }
    }

    /// The choice that an app's stored language list stands for. No list, or
    /// a list that starts with a language Wallnetic is not translated into,
    /// is the system default.
    init(storedLanguages: [String]?) {
        guard let first = storedLanguages?.first else {
            self = .system
            return
        }
        if first.hasPrefix(AppLanguage.simplifiedChinese.rawValue) {
            self = .simplifiedChinese
            return
        }
        let code = first.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? first
        let match = AppLanguage(rawValue: code)
        self = match == nil || match == .system ? .system : match!
    }
}

/// The language choice in Settings > General.
///
/// It reads and writes the app's own language list, the same value macOS
/// keeps for System Settings > Language & Region > Applications. macOS reads
/// that list when an app starts, so a new choice applies after a restart.
final class AppLanguageSettings: ObservableObject {
    static let shared = AppLanguageSettings()
    static let key = "AppleLanguages"

    @Published private(set) var selection: AppLanguage
    /// The choice the running app started with.
    let launchSelection: AppLanguage

    private let defaults: UserDefaults
    private let domain: String

    /// `domain` is the name of the app's own settings. Only that domain is
    /// read: the same key in the global domain is the system's language list,
    /// not a choice made for this app.
    init(defaults: UserDefaults = .standard, domain: String = Bundle.main.bundleIdentifier ?? "") {
        self.defaults = defaults
        self.domain = domain
        let stored = defaults.persistentDomain(forName: domain)?[Self.key] as? [String]
        let current = AppLanguage(storedLanguages: stored)
        selection = current
        launchSelection = current
    }

    /// The running app still shows the language it started with.
    var needsRestart: Bool { selection != launchSelection }

    func select(_ language: AppLanguage) {
        guard language != selection else { return }
        if language == .system {
            defaults.removeObject(forKey: Self.key)
        } else {
            defaults.set([language.rawValue], forKey: Self.key)
        }
        selection = language
    }

    /// Starts a new copy of the app and quits this one, so the new language
    /// applies. The new copy gets the arguments this one was started with:
    /// without them a restarted copy forgets, for example, an option that
    /// was only passed at launch.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = Array(CommandLine.arguments.dropFirst())
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    ErrorReporter.shared.report(error, context: String(localized: "Wallnetic could not restart"))
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }
}
