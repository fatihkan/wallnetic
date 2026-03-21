import SwiftUI
import WidgetKit

/// Medium widget: wallpaper background + large clock + date + controls
struct MediumWidgetView: View {
    let entry: WallpaperEntry

    var body: some View {
        ZStack {
            // Wallpaper thumbnail as full background
            wallpaperBackground

            // Content overlay
            VStack(spacing: 2) {
                // Top: date row
                HStack(alignment: .firstTextBaseline) {
                    Text(dayNumber)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.pink)

                    Text(monthYear)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))

                    Spacer()

                    // Play/Pause + Next
                    HStack(spacing: 12) {
                        Link(destination: URL(string: "wallnetic://playPause")!) {
                            Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.9))
                        }

                        Link(destination: URL(string: "wallnetic://nextWallpaper")!) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial.opacity(0.5))
                    .clipShape(Capsule())
                }

                // Clock - large
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(timeString)
                        .font(.system(size: 52, weight: .ultraLight, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 6, y: 3)

                    Text(dayName)
                        .font(.system(size: 22, weight: .light, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                        .shadow(color: .black.opacity(0.4), radius: 3)
                }

                Spacer()

                // Bottom: wallpaper info + favorites
                HStack(spacing: 8) {
                    // Current wallpaper name
                    HStack(spacing: 4) {
                        Circle()
                            .fill(entry.isPlaying ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)

                        Text(entry.currentWallpaper?.name ?? "No Wallpaper")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }

                    Spacer()

                    // Favorite thumbnails
                    HStack(spacing: 4) {
                        ForEach(entry.favorites.prefix(3)) { fav in
                            Link(destination: URL(string: "wallnetic://setWallpaper?id=\(fav.id.uuidString)")!) {
                                if let image = fav.image {
                                    Image(nsImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 28, height: 18)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 3)
                                                .stroke(
                                                    fav.id == entry.currentWallpaper?.id
                                                        ? Color.accentColor : Color.white.opacity(0.2),
                                                    lineWidth: 1
                                                )
                                        )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial.opacity(0.5))
            }
            .padding(12)
        }
    }

    private var wallpaperBackground: some View {
        Group {
            if let image = entry.currentWallpaper?.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .overlay(
                        LinearGradient(
                            colors: [.black.opacity(0.3), .clear, .black.opacity(0.4)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.1, green: 0.05, blue: 0.2),
                        Color(red: 0.05, green: 0.15, blue: 0.25)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: entry.date)
    }

    private var dayNumber: String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: entry.date)
    }

    private var monthYear: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.locale = Locale(identifier: "tr_TR")
        return f.string(from: entry.date)
    }

    private var dayName: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        f.locale = Locale(identifier: "tr_TR")
        return f.string(from: entry.date).lowercased()
    }
}
