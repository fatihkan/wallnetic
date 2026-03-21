import SwiftUI
import AVKit

/// Full-screen video preview overlay
struct VideoPreviewView: View {
    let wallpaper: Wallpaper
    let onApply: () -> Void
    let onDismiss: () -> Void

    @State private var player: AVPlayer?
    @State private var looper: AVPlayerLooper?
    @State private var isControlsVisible = true
    @State private var hideTimer: Timer?

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Video player
            if let player = player {
                VideoPlayer(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(40)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isControlsVisible.toggle()
                        }
                        resetHideTimer()
                    }
            }

            // Controls overlay
            if isControlsVisible {
                VStack {
                    // Top bar - close button
                    HStack {
                        Spacer()
                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .padding()
                    }

                    Spacer()

                    // Bottom bar - info and actions
                    HStack(spacing: 16) {
                        // Info
                        VStack(alignment: .leading, spacing: 4) {
                            Text(wallpaper.name)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)

                            HStack(spacing: 12) {
                                Label(wallpaper.formattedResolution, systemImage: "aspectratio")
                                Label(wallpaper.formattedDuration, systemImage: "clock")
                                Label(wallpaper.formattedFileSize, systemImage: "doc")
                            }
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        }

                        Spacer()

                        // Play/Pause
                        Button {
                            if player?.rate == 0 {
                                player?.play()
                            } else {
                                player?.pause()
                            }
                        } label: {
                            Image(systemName: player?.rate == 0 ? "play.circle.fill" : "pause.circle.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)

                        // Apply button
                        Button {
                            onApply()
                            onDismiss()
                        } label: {
                            Label("Apply Wallpaper", systemImage: "photo.on.rectangle")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .padding(20)
                    .background(.ultraThinMaterial.opacity(0.8))
                }
                .transition(.opacity)
            }
        }
        .onAppear { setupPlayer() }
        .onDisappear { cleanupPlayer() }
        .onExitCommand { onDismiss() }
    }

    private func setupPlayer() {
        let item = AVPlayerItem(url: wallpaper.url)
        let queuePlayer = AVQueuePlayer(playerItem: item)
        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        queuePlayer.isMuted = true
        player = queuePlayer
        queuePlayer.play()
        resetHideTimer()
    }

    private func cleanupPlayer() {
        hideTimer?.invalidate()
        player?.pause()
        player = nil
        looper = nil
    }

    private func resetHideTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.3)) {
                isControlsVisible = false
            }
        }
    }
}
