import SwiftUI
import AVKit

/// Cinematic full-screen video preview overlay
struct VideoPreviewView: View {
    let wallpaper: Wallpaper
    let onApply: () -> Void
    let onDismiss: () -> Void

    @State private var player: AVPlayer?
    @State private var looper: AVPlayerLooper?
    @State private var isControlsVisible = true
    @State private var hideTimer: Timer?
    @State private var appeared = false

    var body: some View {
        ZStack {
            // Dimmed background with blur
            Color.black.opacity(appeared ? 0.9 : 0)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Video player with cinematic frame
            if let player = player {
                VideoPlayer(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(40)
                    .glowCard(isHovering: true, cornerRadius: 12)
                    .scaleEffect(appeared ? 1.0 : 0.92)
                    .opacity(appeared ? 1 : 0)
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: Anim.normal)) {
                            isControlsVisible.toggle()
                        }
                        resetHideTimer()
                    }
            }

            // Controls overlay
            if isControlsVisible {
                VStack {
                    // Top bar
                    HStack {
                        Spacer()
                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .padding()
                    }

                    Spacer()

                    // Bottom bar with glass effect
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(wallpaper.displayName)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)

                            HStack(spacing: 12) {
                                Label(wallpaper.formattedResolution, systemImage: "aspectratio")
                                Label(wallpaper.formattedDuration, systemImage: "clock")
                                Label(wallpaper.formattedFileSize, systemImage: "doc")
                            }
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                        }

                        Spacer()

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
                                .neonGlow(.white, isActive: true, radius: 6)
                        }
                        .buttonStyle(.plain)

                        Button {
                            onApply()
                            onDismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "photo.on.rectangle")
                                Text("Apply")
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().fill(Color.accentColor)
                            )
                            .foregroundColor(.white)
                            .neonGlow(.accentColor, isActive: true, radius: 8)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(20)
                    .glassBackground(cornerRadius: 16, opacity: 0.1)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 8)
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            setupPlayer()
            withAnimation(.spring(response: Anim.expand, dampingFraction: 0.85)) {
                appeared = true
            }
        }
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
            withAnimation(.easeOut(duration: Anim.medium)) {
                isControlsVisible = false
            }
        }
    }
}
