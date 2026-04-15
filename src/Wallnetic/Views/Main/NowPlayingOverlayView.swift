import SwiftUI

struct NowPlayingOverlayView: View {
    @EnvironmentObject var manager: NowPlayingManager
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            artworkView
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(manager.title.isEmpty ? "—" : manager.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(manager.artist)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)

                progressBar
                    .padding(.top, 4)
            }

            if hovering {
                controls.transition(.opacity)
            }
        }
        .padding(12)
        .frame(width: 340, height: 92)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 0.5)
                )
        )
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
    }

    @ViewBuilder
    private var artworkView: some View {
        if let art = manager.artwork {
            Image(nsImage: art).resizable().scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08))
                .overlay(Image(systemName: "music.note").foregroundColor(.white.opacity(0.5)))
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15)).frame(height: 3)
                Capsule().fill(.white.opacity(0.8))
                    .frame(width: geo.size.width * progressFraction, height: 3)
            }
        }
        .frame(height: 3)
    }

    private var progressFraction: Double {
        guard manager.duration > 0 else { return 0 }
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
        .foregroundColor(.white)
    }
}
