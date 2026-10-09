import SwiftUI

struct StorageSettingsView: View {
    @StateObject private var model: LibraryStorageModel
    @State private var largestFirst = true
    @State private var showingFailures = false

    init(model: LibraryStorageModel? = nil) {
        _model = StateObject(wrappedValue: model ?? LibraryStorageModel(manager: WallpaperManager.shared))
    }

    private var videos: [StorageItem] {
        model.scan.items.filter { $0.category == .videos }.sorted {
            if largestFirst && $0.bytes != $1.bytes { return $0.bytes > $1.bytes }
            return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(size(model.scan.totalBytes)).font(.title2.weight(.semibold))
                    Text("Managed storage").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
                Button("Refresh") { Task { await model.refresh() } }.disabled(model.isBusy)
            }

            HStack(alignment: .top, spacing: 18) {
                ForEach(StorageCategory.allCases, id: \.self) { category in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(category.rawValue).font(.caption).foregroundColor(.secondary)
                        Text(size(model.scan.bytes(in: category))).monospacedDigit()
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text("Only app-managed copies are listed. Your original source files are kept.")
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(model.selection.isEmpty ? "Select all" : "Deselect all") {
                    model.selection = model.selection.isEmpty ? Set(videos.map(\.id)) : []
                }.disabled(model.isBusy || videos.isEmpty)
                Spacer()
                Picker("Sort", selection: $largestFirst) {
                    Text("Largest first").tag(true)
                    Text("Name").tag(false)
                }.frame(width: 205)
            }

            List(videos) { item in
                Toggle(isOn: Binding(
                    get: { model.selection.contains(item.id) },
                    set: { if $0 { model.selection.insert(item.id) } else { model.selection.remove(item.id) } }
                )) {
                    HStack {
                        Text(item.url.lastPathComponent).lineLimit(1).help(item.url.path)
                        Spacer()
                        Text(size(item.bytes)).foregroundColor(.secondary).monospacedDigit()
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(model.isBusy)
                .accessibilityLabel("\(item.url.lastPathComponent), \(size(item.bytes)), app-managed copy")
            }
            .overlay {
                if videos.isEmpty && !model.isBusy {
                    Text("No managed videos").foregroundColor(.secondary)
                }
            }
            .frame(minHeight: 50)

            HStack {
                Button("Remove selected (\(model.selection.count))…", role: .destructive) {
                    Task { await model.prepareRemoval(caches: false) }
                }.disabled(model.isBusy || model.selection.isEmpty)
                Spacer()
                Button("Clear unused caches…") {
                    Task { await model.prepareRemoval(caches: true) }
                }.disabled(model.isBusy)
            }
            Text("Unused widget thumbnails can be cleared. System wallpaper images, current thumbnails and the search index are kept.")
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            if let message = model.message { Text(message).font(.caption) }
            if !model.failures.isEmpty {
                Button("\(model.failures.count) item(s) could not be processed — Show details") {
                    showingFailures = true
                }.font(.caption).foregroundColor(.orange)
            }
        }
        .padding(16)
        .task { await model.refresh() }
        .sheet(isPresented: $showingFailures) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Storage details").font(.headline)
                ScrollView {
                    Text(model.failures.joined(separator: "\n")).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack { Spacer(); Button("Done") { showingFailures = false } }
            }.padding(20).frame(width: 500, height: 300)
        }
        .alert(item: $model.plan) { plan in
            Alert(title: Text(plan.isCacheCleanup ? "Clear \(plan.items.count) cache file(s)?" : "Remove \(plan.items.count) library copy/copies?"),
                  message: Text("Estimated space recovery: \(size(plan.bytes)). Actual disk space recovered may differ.\n\n" +
                    (plan.isCacheCleanup ? "This clears unused thumbnail copies. Your videos, active thumbnails and system wallpaper images are kept." :
                        "This permanently removes the selected app-managed copies and their assignments. Active copies stop playing. Your original source files are kept.")),
                  primaryButton: .destructive(Text("Remove")) { Task { await model.confirmRemoval(plan) } },
                  secondaryButton: .cancel())
        }
    }

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
