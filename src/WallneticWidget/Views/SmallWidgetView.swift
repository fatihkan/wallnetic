import SwiftUI
import WidgetKit

/// Small widget showing current wallpaper with play/pause
struct SmallWidgetView: View {
    let entry: WallpaperEntry

    var body: some View {
        ZStack {
            // Background - current wallpaper thumbnail
            if let wallpaper = entry.currentWallpaper,
               let thumbnailURL = wallpaper.thumbnailURL,
               let imageData = try? Data(contentsOf: thumbnailURL),
               let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Placeholder gradient
                LinearGradient(
                    colors: [.purple.opacity(0.8), .blue.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            // Overlay with controls
            VStack {
                Spacer()

                HStack {
                    // Wallpaper name
                    Text(entry.currentWallpaper?.name ?? "No Wallpaper")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .shadow(radius: 2)

                    Spacer()

                    // Play/Pause indicator
                    if #available(macOS 14.0, *) {
                        Button(intent: PlayPauseIntent()) {
                            playPauseIcon
                        }
                        .buttonStyle(.plain)
                    } else {
                        Link(destination: URL(string: "wallnetic://playPause")!) {
                            playPauseIcon
                        }
                    }
                }
                .padding(8)
                .background(.ultraThinMaterial.opacity(0.8))
            }
        }
        .widgetURL(URL(string: "wallnetic://open"))
    }

    private var playPauseIcon: some View {
        Image(systemName: entry.isPlaying ? "pause.circle.fill" : "play.circle.fill")
            .font(.title2)
            .foregroundColor(.white)
            .shadow(radius: 2)
    }
}
