import SwiftUI
import WidgetKit

/// Medium widget: wallpaper bg + large clock + date + glassmorphism controls
struct MediumWidgetView: View {
    let entry: WallpaperEntry

    var body: some View {
        ZStack {
            wallpaperBackground

            VStack(spacing: 0) {
                // Top: date + controls
                HStack(alignment: .center) {
                    // Day number accent
                    Text(dayNumber)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.pink, .pink.opacity(0.7)],
                                           startPoint: .top, endPoint: .bottom)
                        )

                    VStack(alignment: .leading, spacing: 0) {
                        Text(monthYear)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }

                    Spacer()

                    // Glass control capsule
                    HStack(spacing: 14) {
                        Link(destination: URL(string: "wallnetic://playPause")!) {
                            Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                        }

                        Link(destination: URL(string: "wallnetic://nextWallpaper")!) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial.opacity(0.6))
                            .overlay(
                                Capsule()
                                    .stroke(.white.opacity(0.12), lineWidth: 0.5)
                            )
                    )
                }

                // Clock + day name
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(timeString)
                        .font(.system(size: 54, weight: .ultraLight, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 10, y: 3)
                        .tracking(1)

                    Text(dayName)
                        .font(.system(size: 20, weight: .light, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))

                    Spacer()
                }
                .padding(.top, -4)

                Spacer()

                // Bottom glass bar: status + favorite thumbnails
                HStack(spacing: 8) {
                    Circle()
                        .fill(entry.isPlaying ? Color.green : Color.orange)
                        .frame(width: 5, height: 5)

                    Text(entry.currentWallpaper?.name ?? "No Wallpaper")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)

                    Spacer()

                    // Favorite mini thumbnails
                    HStack(spacing: 3) {
                        ForEach(entry.favorites.prefix(4)) { fav in
                            Link(destination: URL(string: "wallnetic://setWallpaper?id=\(fav.id.uuidString)")!) {
                                Group {
                                    if let image = fav.image {
                                        Image(nsImage: image)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } else {
                                        Color.white.opacity(0.1)
                                    }
                                }
                                .frame(width: 24, height: 16)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(
                                            fav.id == entry.currentWallpaper?.id
                                                ? Color.pink.opacity(0.8)
                                                : Color.white.opacity(0.15),
                                            lineWidth: fav.id == entry.currentWallpaper?.id ? 1.5 : 0.5
                                        )
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    ContainerRelativeShape()
                        .inset(by: -1)
                        .fill(.ultraThinMaterial.opacity(0.6))
                )
                .overlay(
                    ContainerRelativeShape()
                        .inset(by: -1)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
            }
            .padding(12)
        }
        .clipShape(ContainerRelativeShape())
    }

    private var wallpaperBackground: some View {
        Group {
            if let image = entry.currentWallpaper?.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .overlay(
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(0.35), location: 0),
                                .init(color: .black.opacity(0.1), location: 0.4),
                                .init(color: .black.opacity(0.45), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else {
                ZStack {
                    Color(red: 0.06, green: 0.06, blue: 0.12)
                    LinearGradient(
                        colors: [.purple.opacity(0.3), .blue.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
        }
    }

    private var timeString: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: entry.date)
    }
    private var dayNumber: String {
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: entry.date)
    }
    private var monthYear: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; f.locale = Locale.current; return f.string(from: entry.date)
    }
    private var dayName: String {
        let f = DateFormatter(); f.dateFormat = "EEEE"; f.locale = Locale.current; return f.string(from: entry.date).lowercased()
    }
}
