import SwiftUI

struct PlaybackStatusView: View {
    let status: DisplayPlaybackStatus
    var showsDisplayName = false
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(showsDisplayName ? "\(status.displayName): \(status.title)" : status.title,
                  systemImage: status.symbol)
                .font(.caption)
                .accessibilityLabel("\(status.displayName): \(status.title)")
            if !status.detail.isEmpty {
                Text(status.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if status.canRetry {
                Button("Retry wallpaper", action: retry)
                    .font(.caption)
                    .accessibilityLabel("Retry wallpaper on \(status.displayName)")
                    .help("Reload this wallpaper while keeping manual pause and power restrictions.")
            }
        }
        .accessibilityElement(children: .contain)
    }
}
