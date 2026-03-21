import SwiftUI
import WidgetKit

/// Small widget: wallpaper background + clock + play/pause
struct SmallWidgetView: View {
    let entry: WallpaperEntry

    var body: some View {
        ZStack {
            // Wallpaper thumbnail as background
            wallpaperBackground

            // Glass overlay with clock
            VStack(spacing: 4) {
                Spacer()

                // Clock
                Text(timeString)
                    .font(.system(size: 36, weight: .thin, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 2)

                // Date
                Text(dateString)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.4), radius: 2)

                Spacer()

                // Controls bar
                HStack {
                    // Wallpaper name
                    Text(entry.currentWallpaper?.name ?? "Wallnetic")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)

                    Spacer()

                    // Play/Pause
                    Link(destination: URL(string: "wallnetic://playPause")!) {
                        Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial.opacity(0.6))
            }
        }
    }

    private var wallpaperBackground: some View {
        Group {
            if let image = entry.currentWallpaper?.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .overlay(Color.black.opacity(0.2))
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.1, green: 0.05, blue: 0.2),
                        Color(red: 0.05, green: 0.1, blue: 0.25)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: entry.date)
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM, EEEE"
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter.string(from: entry.date)
    }
}
