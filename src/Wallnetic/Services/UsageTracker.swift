import Foundation
import SwiftUI

/// Tracks AI generation usage and enforces limits
class UsageTracker: ObservableObject {
    static let shared = UsageTracker()

    static let dailyLimit = 10
    static let monthlyLimit = 100

    @Published var todayCount: Int = 0
    @Published var monthCount: Int = 0
    @Published var isLoading = false

    @AppStorage("usage.lastResetDate") private var lastResetDate: String = ""

    var remainingToday: Int {
        max(0, Self.dailyLimit - todayCount)
    }

    var remainingMonth: Int {
        max(0, Self.monthlyLimit - monthCount)
    }

    var canGenerate: Bool {
        // If not authenticated, allow unlimited (uses local API key)
        guard AuthManager.shared.isAuthenticated else { return true }
        return remainingToday > 0 && remainingMonth > 0
    }

    var limitMessage: String? {
        guard AuthManager.shared.isAuthenticated else { return nil }

        if remainingToday == 0 {
            return "Daily limit reached (\(Self.dailyLimit)/day). Try again tomorrow."
        }
        if remainingMonth == 0 {
            return "Monthly limit reached (\(Self.monthlyLimit)/month)."
        }
        return nil
    }

    private init() {
        checkDailyReset()
    }

    // MARK: - Track Generation

    func trackGeneration() {
        todayCount += 1
        monthCount += 1

        // Sync to cloud if authenticated
        if AuthManager.shared.isAuthenticated {
            Task {
                await syncUsageToCloud()
            }
        }

        // Save locally
        UserDefaults.standard.set(todayCount, forKey: "usage.todayCount")
        UserDefaults.standard.set(monthCount, forKey: "usage.monthCount")
    }

    // MARK: - Fetch from Cloud

    func refreshFromCloud() async {
        guard AuthManager.shared.isAuthenticated else { return }

        await MainActor.run { isLoading = true }

        do {
            let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
            let monthStart = "\(today.prefix(7))-01"

            // Fetch today's usage
            let (todayData, _) = try await SupabaseClient.shared.request(
                path: "/rest/v1/usage?date=eq.\(today)&select=generation_count",
                method: "GET"
            )

            if let todayArr = try JSONSerialization.jsonObject(with: todayData) as? [[String: Any]],
               let first = todayArr.first,
               let count = first["generation_count"] as? Int {
                await MainActor.run { todayCount = count }
            }

            // Fetch monthly usage (sum of all days in current month)
            let (monthData, _) = try await SupabaseClient.shared.request(
                path: "/rest/v1/usage?date=gte.\(monthStart)&select=generation_count",
                method: "GET"
            )

            if let monthArr = try JSONSerialization.jsonObject(with: monthData) as? [[String: Any]] {
                let total = monthArr.compactMap { $0["generation_count"] as? Int }.reduce(0, +)
                await MainActor.run { monthCount = total }
            }

        } catch {
            NSLog("[UsageTracker] Refresh error: %@", error.localizedDescription)
        }

        await MainActor.run { isLoading = false }
    }

    // MARK: - Private

    private func syncUsageToCloud() async {
        guard let userId = AuthManager.shared.userId else { return }

        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)

        do {
            _ = try await SupabaseClient.shared.request(
                path: "/rest/v1/usage",
                method: "POST",
                body: [
                    "user_id": userId,
                    "date": String(today),
                    "generation_count": todayCount
                ],
                headers: [
                    "Prefer": "resolution=merge-duplicates",
                    "On-Conflict": "user_id,date"
                ]
            )
        } catch {
            NSLog("[UsageTracker] Sync error: %@", error.localizedDescription)
        }
    }

    private func checkDailyReset() {
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let todayStr = String(today)

        if lastResetDate != todayStr {
            todayCount = 0
            UserDefaults.standard.set(0, forKey: "usage.todayCount")
            lastResetDate = todayStr
        } else {
            todayCount = UserDefaults.standard.integer(forKey: "usage.todayCount")
            monthCount = UserDefaults.standard.integer(forKey: "usage.monthCount")
        }
    }
}

// MARK: - Usage Badge View

struct UsageBadgeView: View {
    @ObservedObject var tracker = UsageTracker.shared
    @ObservedObject var auth = AuthManager.shared

    var body: some View {
        if auth.isAuthenticated {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .foregroundColor(tracker.remainingToday > 3 ? .green : .orange)

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(tracker.remainingToday) left today")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("\(tracker.remainingMonth)/\(UsageTracker.monthlyLimit) this month")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(.secondary.opacity(0.1)))
        }
    }
}
