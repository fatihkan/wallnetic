import SwiftUI

struct NowPlayingOverlayView: View {
    @EnvironmentObject var manager: NowPlayingManager
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            artworkView
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(titleText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitleText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                progressBar
                    .padding(.top, 4)
            }

            Spacer(minLength: 4)

            controls
                .opacity(manager.hasTrack ? (hovering ? 1 : 0.6) : 0.3)
                .animation(.easeInOut(duration: 0.15), value: hovering)
                .animation(.easeInOut(duration: 0.15), value: manager.hasTrack)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 340, height: 92)
        // The card fills its panel, so it casts no shadow of its own.
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous)) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
        }
        .onHover { hovering = $0 }
    }

    // MARK: - Pieces

    private var titleText: String {
        manager.hasTrack ? manager.title : "Nothing playing"
    }

    private var subtitleText: String {
        if manager.hasTrack {
            return manager.artist.isEmpty ? manager.album : manager.artist
        }
        return "Waiting for a track…"
    }

    @ViewBuilder
    private var artworkView: some View {
        if let art = manager.artwork {
            Image(nsImage: art).resizable().scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.08))
                Image(systemName: "music.note")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.15)).frame(height: 3)
                Capsule().fill(Color.primary.opacity(0.75))
                    .frame(width: geo.size.width * progressFraction, height: 3)
            }
        }
        .frame(height: 3)
    }

    private var progressFraction: Double {
        guard manager.hasTrack, manager.duration > 0 else { return 0 }
        return max(0, min(1, manager.elapsed / manager.duration))
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button { manager.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 12))
            }
            Button { manager.togglePlayPause() } label: {
                Image(systemName: manager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
            }
            Button { manager.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 12))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .disabled(!manager.hasTrack)
    }
}
