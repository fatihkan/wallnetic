import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct OnboardingQuickStartView: View {
    @StateObject private var model = OnboardingDemoModel()
    @State private var screens = NSScreen.screens
    @State private var target: UInt32 = 0
    @State private var importing = false
    @State private var importTarget: UInt32?

    var body: some View {
        VStack(spacing: 8) {
            Picker("Apply to", selection: $target) {
                Text("All displays (default)").tag(UInt32(0))
                ForEach(screens, id: \.self) { screen in
                    if let id = screen.displayID { Text(screen.localizedName).tag(id) }
                }
            }
            .frame(maxWidth: 340)
            .disabled(model.isWorking)
            HStack(spacing: 12) {
                Button("Try a sample") { model.trySample(on: target == 0 ? nil : target) }
                    .buttonStyle(.borderedProminent)
                Button("Import my video…") {
                    importTarget = target == 0 ? nil : target
                    importing = true
                }
                .buttonStyle(.bordered)
            }
            .disabled(model.isWorking)
            Text("Included sample · 720p · 6 seconds · under 400 KB · Works offline")
                .font(.caption).foregroundStyle(.secondary)
            if model.isWorking {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Preparing wallpaper…").font(.caption)
                    Button("Cancel") { model.cancel() }.font(.caption)
                }
            } else if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.primary)
                    .accessibilityLabel("Could not apply wallpaper. \(error)")
            } else {
                Text(model.message ?? "Adds a removable copy to Library. Your own videos stay untouched.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 510)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.movie], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { model.importFile(url, on: importTarget) }
            case .failure(let error): model.reportImportError(error)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
            // Never silently redirect a running operation to another display.
            if !model.isWorking, target != 0, !screens.contains(where: { $0.displayID == target }) { target = 0 }
        }
        .onDisappear { model.cancel() }
    }
}
