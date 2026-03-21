import SwiftUI
import WidgetKit

/// Small widget: wallpaper bg + frosted glass clock + controls
struct SmallWidgetView: View {
    let entry: WallpaperEntry

    var body: some View {
        ZStack {
            wallpaperBackground

            // Frosted glass panel
            VStack(spacing: 6) {
                Spacer()

                // Clock
                Text(timeString)
                    .font(.system(size: 38, weight: .light, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
                    .tracking(2)

                // Date
                Text(shortDateString)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
                    .tracking(1)

                Spacer()

                // Bottom glass bar
                HStack(spacing: 6) {
                    Circle()
                        .fill(entry.isPlaying ? Color.green : Color.orange)
                        .frame(width: 5, height: 5)

                    Text(entry.currentWallpaper?.name ?? "Wallnetic")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)

                    Spacer()

                    Link(destination: URL(string: "wallnetic://playPause")!) {
                        Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 22, height: 22)
                            .background(.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial.opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.white.opacity(0.12), lineWidth: 0.5)
                        )
                )
            }
            .padding(8)
        }
    }

    private var wallpaperBackground: some View {
        Group {
            if let image = entry.currentWallpaper?.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .overlay(Color.black.opacity(0.25))
            } else {
                ZStack {
                    Color(red: 0.06, green: 0.06, blue: 0.12)
                    LinearGradient(
                        colors: [.purple.opacity(0.3), .blue.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
        }
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: entry.date)
    }

    private var shortDateString: String {
        let f = DateFormatter()
        f.dateFormat = "d MMM, EEE"
        f.locale = Locale(identifier: "tr_TR")
        return f.string(from: entry.date).uppercased()
    }
}
