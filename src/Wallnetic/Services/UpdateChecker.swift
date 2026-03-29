import Foundation
import SwiftUI

/// Checks for app updates via GitHub Releases API
class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var downloadURL: URL?
    @Published var isChecking = false

    @AppStorage("update.autoCheck") var autoCheck: Bool = true
    @AppStorage("update.lastCheckDate") private var lastCheckTimestamp: Double = 0

    private let repoOwner = "fatihkan"
    private let repoName = "wallnetic"
    private let currentVersion: String

    private init() {
        currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        if autoCheck { checkAfterDelay() }
    }

    private func checkAfterDelay() {
        // Check at most once per day
        let lastCheck = Date(timeIntervalSince1970: lastCheckTimestamp)
        guard Date().timeIntervalSince(lastCheck) > 86400 else { return }

        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s delay after launch
            await checkForUpdates()
        }
    }

    @MainActor
    func checkForUpdates() async {
        isChecking = true
        defer { isChecking = false }

        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else { return }

            let latest = tagName.replacingOccurrences(of: "v", with: "")
            latestVersion = latest

            if isNewerVersion(latest, than: currentVersion) {
                updateAvailable = true
                if let assets = json["assets"] as? [[String: Any]],
                   let asset = assets.first,
                   let urlStr = asset["browser_download_url"] as? String {
                    downloadURL = URL(string: urlStr)
                }
            }

            lastCheckTimestamp = Date().timeIntervalSince1970
        } catch {
            NSLog("[UpdateChecker] Error: %@", error.localizedDescription)
        }
    }

    private func isNewerVersion(_ new: String, than current: String) -> Bool {
        new.compare(current, options: .numeric) == .orderedDescending
    }
}
