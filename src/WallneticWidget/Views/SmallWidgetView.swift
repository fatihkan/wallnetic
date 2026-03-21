import SwiftUI
import WidgetKit

/// Small widget showing current wallpaper with play/pause
struct SmallWidgetView: View {
    let entry: WallpaperEntry

    var body: some View {
        ZStack {
            // Background - current wallpaper thumbnail
            if let image = entry.currentWallpaper?.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
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
                    Text(entry.currentWallpaper?.name ?? "No Wallpaper")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .shadow(radius: 2)

                    Spacer()

                    Link(destination: URL(string: "wallnetic://playPause")!) {
                        Image(systemName: entry.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                    }
                }
                .padding(8)
                .background(.ultraThinMaterial.opacity(0.8))
            }
        }
    }
}
