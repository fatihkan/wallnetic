import SwiftUI

/// Settings panel for the optional Ollama Vision auto-tagger (#116).
struct SmartTaggingSettingsView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @ObservedObject private var service = OllamaTaggingService.shared

    @State private var endpoint: String = ""
    @State private var model: String = ""

    var body: some View {
        Form {
            Section {
                Text("Smart Tagging uses a local Ollama vision model to read each wallpaper thumbnail and suggest tags. Ollama must be running on your Mac — nothing is sent to the cloud.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Ollama Server") {
                LabeledContent("Endpoint") {
                    TextField("http://localhost:11434/api/generate", text: $endpoint)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                        .onChange(of: endpoint) { _ in
                            // Persist live so validation reflects what the
                            // user sees, and consent gets invalidated.
                            service.endpointString = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                }
                if let reason = service.endpointValidationError {
                    Label(reason, systemImage: "shield.lefthalf.filled.slash")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Text("Only loopback (localhost / 127.0.0.1 / ::1) or *.local (https) hosts are allowed — your wallpaper thumbnails never leave this Mac/LAN.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                LabeledContent("Model") {
                    TextField("llava", text: $model)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }
                Text("Suggested models: llava, llava:13b, bakllava. Larger models give better tags but take longer.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Section("Run") {
                HStack {
                    Button(service.isRunning ? "Cancel" : "Tag Untagged Wallpapers") {
                        if service.isRunning {
                            service.cancel()
                        } else {
                            commitSettings()
                            service.tagAll(
                                wallpapers: wallpaperManager.wallpapers,
                                manager: wallpaperManager
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!service.isRunning && service.endpointValidationError != nil)

                    Spacer()
                }

                if service.isRunning || service.progress > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: service.progress)
                        Text(service.statusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let error = service.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            endpoint = service.endpointString
            model = service.modelName
        }
        .onDisappear { commitSettings() }
    }

    private func commitSettings() {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEndpoint.isEmpty { service.endpointString = trimmedEndpoint }
        if !trimmedModel.isEmpty { service.modelName = trimmedModel }
    }
}
