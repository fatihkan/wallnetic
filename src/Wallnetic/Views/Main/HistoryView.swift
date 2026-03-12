import SwiftUI

struct HistoryView: View {
    @ObservedObject private var historyManager = GenerationHistoryManager.shared
    @EnvironmentObject var wallpaperManager: WallpaperManager

    @State private var selectedItem: GenerationHistoryItem?
    @State private var showingDeleteConfirmation = false
    @State private var showingClearAllConfirmation = false
    @State private var itemToDelete: GenerationHistoryItem?

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content
            if historyManager.items.isEmpty {
                emptyStateView
            } else {
                historyGridView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $selectedItem) { item in
            HistoryDetailView(item: item, onDismiss: { selectedItem = nil })
        }
        .alert("Delete Generation", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    historyManager.deleteItem(item)
                }
            }
        } message: {
            Text("Are you sure you want to delete this generation? This cannot be undone.")
        }
        .alert("Clear All History", isPresented: $showingClearAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                historyManager.clearAll()
            }
        } message: {
            Text("Are you sure you want to delete all generation history? This cannot be undone.")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Generation History")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("\(historyManager.items.count) generations")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !historyManager.items.isEmpty {
                Button(role: .destructive) {
                    showingClearAllConfirmation = true
                } label: {
                    Text("Clear All")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("No Generation History")
                    .font(.headline)

                Text("Your AI-generated wallpapers will appear here")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - History Grid

    private var historyGridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(historyManager.items) { item in
                    HistoryItemCard(
                        item: item,
                        thumbnail: historyManager.getThumbnail(for: item),
                        onTap: { selectedItem = item },
                        onDelete: {
                            itemToDelete = item
                            showingDeleteConfirmation = true
                        }
                    )
                }
            }
            .padding()
        }
    }
}

// MARK: - History Item Card

struct HistoryItemCard: View {
    let item: GenerationHistoryItem
    let thumbnail: NSImage?
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 8) {
            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.05))

                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 100)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                }

                // Hover overlay
                if isHovering {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.4))

                    HStack(spacing: 16) {
                        Button {
                            onTap()
                        } label: {
                            Image(systemName: "eye.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)

                        Button {
                            onDelete()
                        } label: {
                            Image(systemName: "trash.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                    }
                }

                // Style badge
                VStack {
                    HStack {
                        Spacer()
                        if item.wasImg2Img {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption2)
                                .padding(4)
                                .background(.ultraThinMaterial)
                                .cornerRadius(4)
                        }
                    }
                    Spacer()
                }
                .padding(6)
            }
            .frame(height: 100)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.styleName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(item.relativeDate)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovering ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 2)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - History Detail View

struct HistoryDetailView: View {
    let item: GenerationHistoryItem
    let onDismiss: () -> Void

    @ObservedObject private var historyManager = GenerationHistoryManager.shared
    @State private var fullImage: NSImage?
    @State private var isApplying = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Generation Details")
                    .font(.headline)

                Spacer()

                // Spacer for symmetry
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .opacity(0)
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                VStack(spacing: 24) {
                    // Image preview
                    if let image = fullImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(height: 200)
                            .overlay(
                                ProgressView()
                            )
                    }

                    // Details
                    VStack(alignment: .leading, spacing: 16) {
                        DetailRow(label: "Style", value: item.styleName)
                        DetailRow(label: "Provider", value: item.provider)
                        DetailRow(label: "Resolution", value: "\(item.width) × \(item.height)")
                        DetailRow(label: "Created", value: item.formattedDate)

                        if item.wasImg2Img {
                            DetailRow(label: "Type", value: "Image-to-Image")
                            if let strength = item.strength {
                                DetailRow(label: "Strength", value: "\(Int(strength * 100))%")
                            }
                        } else {
                            DetailRow(label: "Type", value: "Text-to-Image")
                        }

                        if !item.prompt.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Prompt")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text(item.prompt)
                                    .font(.subheadline)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.horizontal)

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding()
            }

            Divider()

            // Actions
            HStack(spacing: 12) {
                Button {
                    onDismiss()
                } label: {
                    Text("Close")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape)

                Spacer()

                Button {
                    applyAsWallpaper()
                } label: {
                    HStack {
                        if isApplying {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "desktopcomputer")
                        }
                        Text("Set as Wallpaper")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(fullImage == nil || isApplying)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
        .onAppear {
            loadFullImage()
        }
    }

    private func loadFullImage() {
        fullImage = historyManager.getImage(for: item)
    }

    private func applyAsWallpaper() {
        guard let image = fullImage,
              let imageURL = item.imageURL else { return }

        isApplying = true
        errorMessage = nil

        Task {
            do {
                try await MainActor.run {
                    for screen in NSScreen.screens {
                        try NSWorkspace.shared.setDesktopImageURL(imageURL, for: screen, options: [:])
                    }
                }
                await MainActor.run {
                    isApplying = false
                    onDismiss()
                }
            } catch {
                await MainActor.run {
                    isApplying = false
                    errorMessage = "Failed to apply: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.subheadline)
        }
    }
}

// MARK: - Preview

#Preview {
    HistoryView()
        .frame(width: 600, height: 500)
}
