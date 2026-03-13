import SwiftUI
import AVKit

struct HistoryView: View {
    @ObservedObject private var historyManager = GenerationHistoryManager.shared
    @EnvironmentObject var wallpaperManager: WallpaperManager

    @State private var selectedItem: GenerationHistoryItem?
    @State private var showingDeleteConfirmation = false
    @State private var showingClearAllConfirmation = false
    @State private var itemToDelete: GenerationHistoryItem?

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)
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
        .alert("Delete Video", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    historyManager.deleteItem(item)
                }
            }
        } message: {
            Text("Are you sure you want to delete this video? This cannot be undone.")
        }
        .alert("Clear All History", isPresented: $showingClearAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                historyManager.clearAll()
            }
        } message: {
            Text("Are you sure you want to delete all video history? This cannot be undone.")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Video Generation History")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("\(historyManager.items.count) videos")
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
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("No Video History")
                    .font(.headline)

                Text("Your AI-generated videos will appear here")
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
                    VideoHistoryCard(
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

// MARK: - Video History Card

struct VideoHistoryCard: View {
    let item: GenerationHistoryItem
    let thumbnail: NSImage?
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 8) {
            // Thumbnail with video indicator
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.1))

                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 110)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    Image(systemName: "film")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                }

                // Play icon overlay
                if !isHovering {
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "play.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 16))
                        )
                }

                // Hover overlay
                if isHovering {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.5))

                    HStack(spacing: 20) {
                        Button {
                            onTap()
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.title)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)

                        Button {
                            onDelete()
                        } label: {
                            Image(systemName: "trash.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                    }
                }

                // Duration badge
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 2) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text("\(item.duration)s")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial)
                        .cornerRadius(4)
                    }
                    Spacer()
                }
                .padding(6)

                // Img2Vid badge
                if item.wasImg2Vid {
                    VStack {
                        HStack {
                            Image(systemName: "photo.badge.arrow.down")
                                .font(.caption2)
                                .padding(4)
                                .background(.ultraThinMaterial)
                                .cornerRadius(4)
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(6)
                }
            }
            .frame(height: 110)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.modelDisplayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack {
                    Text(item.relativeDate)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(item.aspectRatio)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
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
    @State private var player: AVPlayer?
    @State private var isImporting = false
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

                Text("Video Details")
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
                    // Video player
                    if let player = player {
                        VideoPlayer(player: player)
                            .frame(height: 280)
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
                            .onAppear {
                                player.play()
                            }
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(height: 280)
                            .overlay(
                                ProgressView()
                            )
                    }

                    // Details
                    VStack(alignment: .leading, spacing: 16) {
                        VideoDetailRow(label: "Model", value: item.modelDisplayName)
                        VideoDetailRow(label: "Duration", value: "\(item.duration) seconds")
                        VideoDetailRow(label: "Aspect Ratio", value: item.aspectRatio)
                        VideoDetailRow(label: "Created", value: item.formattedDate)
                        VideoDetailRow(label: "Type", value: item.wasImg2Vid ? "Image-to-Video" : "Text-to-Video")

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
                    importToLibrary()
                } label: {
                    HStack {
                        if isImporting {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text("Add to Library")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(player == nil || isImporting)
            }
            .padding()
        }
        .frame(width: 550, height: 650)
        .onAppear {
            loadVideo()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private func loadVideo() {
        guard let videoURL = item.videoURL else { return }
        player = AVPlayer(url: videoURL)
        player?.actionAtItemEnd = .none

        // Loop the video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }

    private func importToLibrary() {
        guard let videoURL = item.videoURL else { return }

        isImporting = true
        errorMessage = nil

        Task {
            do {
                _ = try await WallpaperManager.shared.importVideo(from: videoURL)
                await MainActor.run {
                    isImporting = false
                    onDismiss()
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    errorMessage = "Failed to import: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Video Detail Row

struct VideoDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(.subheadline)
        }
    }
}

// MARK: - Preview

#Preview {
    HistoryView()
        .frame(width: 700, height: 500)
}
