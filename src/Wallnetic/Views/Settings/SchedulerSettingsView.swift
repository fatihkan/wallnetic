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

                        // Video model selection
                        modelSection

                        Divider()

                        // Duration selection
                        durationSection

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
        .frame(width: 420, height: 550)
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
                Text("Scheduled Video Generation")
                    .font(.headline)

                Text("Auto-generate anime wallpaper videos daily")
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
                Text("Enable Daily Scheduler")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Generate anime video wallpapers automatically")
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

    // MARK: - Model Section

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles.tv")
                    .foregroundColor(.accentColor)
                Text("Video Model")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Toggle("Use random anime model", isOn: $scheduler.useRandomModel)

            if !scheduler.useRandomModel {
                Picker("Model", selection: $scheduler.selectedModel) {
                    ForEach(VideoModel.allCases, id: \.self) { model in
                        HStack {
                            Image(systemName: model.icon)
                            Text(model.displayName)
                            if model.isAnimeOptimized {
                                Text("Anime")
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.pink.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }
                        .tag(model)
                    }
                }
                .pickerStyle(.menu)

                Text(scheduler.selectedModel.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Random anime-optimized models: Kling, Minimax, Pika")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Check API key status
            if KeychainManager.shared.getAPIKey(for: .falai) == nil {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("No fal.ai API key configured")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    // MARK: - Duration Section

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "timer")
                    .foregroundColor(.accentColor)
                Text("Video Duration")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Picker("Duration", selection: $scheduler.videoDuration) {
                Text("5 seconds").tag(5)
                Text("10 seconds").tag(10)
            }
            .pickerStyle(.segmented)

            // Cost estimate
            let estimatedCost = scheduler.selectedModel.costPerSecond * Double(scheduler.videoDuration)
            Text("Estimated cost: $\(String(format: "%.2f", estimatedCost)) per generation")
                .font(.caption)
                .foregroundColor(.secondary)
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
                        Text("Generating video...")
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
