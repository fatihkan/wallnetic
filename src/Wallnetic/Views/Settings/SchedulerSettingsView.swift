import SwiftUI

struct SchedulerSettingsView: View {
    @ObservedObject var scheduler = SchedulerService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Settings
            ScrollView {
                VStack(spacing: 24) {
                    // Enable toggle
                    enableSection

                    if scheduler.isEnabled {
                        Divider()

                        // Time picker
                        timeSection

                        Divider()

                        // Style selection
                        styleSection

                        Divider()

                        // Provider selection
                        providerSection

                        Divider()

                        // Status
                        statusSection
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            footerView
        }
        .frame(width: 400, height: 500)
        .onAppear {
            scheduler.requestNotificationPermission()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "clock.badge.checkmark")
                .font(.title2)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Scheduled Generation")
                    .font(.headline)

                Text("Auto-generate wallpaper at a specific time")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Enable Section

    private var enableSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Enable Scheduler")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Automatically generate and set wallpaper")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: $scheduler.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.1))
        )
    }

    // MARK: - Time Section

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.accentColor)
                Text("Schedule Time (Turkey)")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            HStack(spacing: 8) {
                // Hour picker
                Picker("Hour", selection: $scheduler.scheduleHour) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(String(format: "%02d", hour)).tag(hour)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 70)

                Text(":")
                    .font(.title2)
                    .fontWeight(.medium)

                // Minute picker
                Picker("Minute", selection: $scheduler.scheduleMinute) {
                    ForEach([0, 15, 30, 45], id: \.self) { minute in
                        Text(String(format: "%02d", minute)).tag(minute)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 70)

                Spacer()

                Text("Europe/Istanbul")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
        }
    }

    // MARK: - Style Section

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "paintpalette")
                    .foregroundColor(.accentColor)
                Text("Style")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Toggle("Use random style", isOn: $scheduler.useRandomStyle)

            if !scheduler.useRandomStyle {
                Picker("Style", selection: $scheduler.selectedStyleId) {
                    ForEach(AIStyle.allStyles) { style in
                        HStack {
                            Image(systemName: style.icon)
                            Text(style.name)
                        }
                        .tag(style.id)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    // MARK: - Provider Section

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cpu")
                    .foregroundColor(.accentColor)
                Text("AI Provider")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Picker("Provider", selection: $scheduler.selectedProvider) {
                ForEach(AIProvider.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.segmented)

            // Check API key status
            if KeychainManager.shared.getAPIKey(for: scheduler.selectedProvider) == nil {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("No API key configured for \(scheduler.selectedProvider.displayName)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.accentColor)
                Text("Status")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            VStack(alignment: .leading, spacing: 8) {
                if let nextTime = scheduler.formattedNextScheduledTime {
                    HStack {
                        Text("Next generation:")
                            .foregroundColor(.secondary)
                        Text(nextTime)
                            .fontWeight(.medium)
                    }
                    .font(.caption)
                }

                if let lastGen = scheduler.lastGenerationDate {
                    HStack {
                        Text("Last generation:")
                            .foregroundColor(.secondary)
                        Text(formatDate(lastGen))
                            .fontWeight(.medium)
                    }
                    .font(.caption)
                }

                if scheduler.isGenerating {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Generating...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let error = scheduler.lastError {
                    HStack {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.05))
            )
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button("Test Now") {
                scheduler.triggerNow()
            }
            .buttonStyle(.bordered)
            .disabled(scheduler.isGenerating || !scheduler.isEnabled)

            Spacer()

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.escape)
        }
        .padding()
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy HH:mm"
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    SchedulerSettingsView()
}
