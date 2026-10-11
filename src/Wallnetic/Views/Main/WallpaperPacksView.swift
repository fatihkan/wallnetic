import SwiftUI

struct WallpaperPacksView: View {
    @ObservedObject var model: WallpaperPacksModel
    @Environment(\.dismiss) private var dismiss
    @State private var removalID: String?
    @State private var showingLicense = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wallpaper Packs").font(.title2.bold())
                    Text("Optional downloads from Wallnetic on GitHub. No account required.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                Text(model.catalogSource).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Refresh Catalog") { model.refresh() }.disabled(model.busy)
                Button("Content License") { showingLicense = true }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if let catalog = model.catalog {
                        if catalog.packs.isEmpty {
                            Text("No packs are currently offered. Downloaded wallpapers remain in your library.")
                        }
                        ForEach(catalog.packs) { pack in
                            packCard(pack)
                        }
                        ForEach(model.installedPackIDs.filter { id in !catalog.packs.contains { $0.id == id } }, id: \.self) { id in
                            HStack {
                                Text("Previously downloaded: \(id)")
                                Spacer()
                                Button("Remove Copies…", role: .destructive) { removalID = id }
                                    .disabled(model.busy || model.ownershipError)
                            }
                        }
                    } else {
                        Text("Your local wallpapers are available in Library while the catalog is unavailable.")
                    }
                }
            }
            Text(model.status).font(.callout).foregroundStyle(.secondary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Text("Downloads add library copies without starting playback. Closing this window keeps the current download running.")
                .font(.caption).foregroundStyle(.secondary)
            if model.busy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Working…").font(.caption)
                    Spacer()
                    if !model.isRemoving { Button("Cancel") { model.cancel() } }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 640, idealWidth: 740, maxWidth: 960, minHeight: 540, idealHeight: 700)
        .alert("Remove downloaded copies?", isPresented: Binding(get: { removalID != nil }, set: { if !$0 { removalID = nil } })) {
            Button("Cancel", role: .cancel) { removalID = nil }
            Button("Remove", role: .destructive) {
                if let id = removalID { model.removePack(id) }
                removalID = nil
            }
        } message: {
            Text("This removes verified pack copies from your library, including their playlist and schedule references. Changed files and unrelated imports are kept.")
        }
        .sheet(isPresented: $showingLicense) {
            VStack(alignment: .leading, spacing: 16) {
                Text("MIT Content License").font(.title2.bold())
                ScrollView {
                    Text(Self.licenseText).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Done") { showingLicense = false }.keyboardShortcut(.cancelAction)
            }.padding(24).frame(width: 580, height: 470)
        }
    }

    @ViewBuilder
    private func packCard(_ pack: WallpaperPack) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(pack.name).font(.title3.bold())
            Text(pack.summary).foregroundStyle(.secondary)
            ForEach(pack.items) { item in
                HStack(alignment: .top, spacing: 16) {
                    if let data = Data(base64Encoded: item.previewJPEG), let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                            .frame(width: 180, height: 102).clipShape(RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel("\(item.name) wallpaper preview")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).font(.headline)
                        Text("\(item.width) × \(item.height) · \(Int(item.fps)) fps · \(Int(item.duration)) s · Silent H.264")
                        Text("\(format(item.bytes)) · macOS 13 or later")
                        Text("\(item.creator) · \(item.license)")
                        Text(item.attribution).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.font(.caption)
                }
            }
            HStack {
                Text("\(pack.items.count) wallpapers · \(format(pack.bytes)) total").font(.callout)
                Spacer()
                if model.trackedCount(pack.id) > 0 {
                    Button("Remove Copies…", role: .destructive) { removalID = pack.id }
                        .disabled(model.busy || model.ownershipError)
                }
                Button(model.trackedCount(pack.id) > 0 ? "Download / Retry" : "Download Pack") { model.download(pack) }
                    .disabled(model.busy || model.ownershipError)
            }
            if model.activePackID == pack.id && !model.isRemoving {
                ProgressView(value: Double(model.downloadedBytes), total: Double(pack.bytes))
                    .accessibilityLabel("Pack download progress")
                Text("\(format(model.downloadedBytes)) of \(format(pack.bytes))").font(.caption.monospacedDigit())
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
    }

    private func format(_ bytes: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }
    static var licenseText: String {
        Bundle(for: WallpaperPacksModel.self).url(forResource: "pack-LICENSE-MIT", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "License unavailable. See the MIT LICENSE in the Wallnetic repository."
    }
}
