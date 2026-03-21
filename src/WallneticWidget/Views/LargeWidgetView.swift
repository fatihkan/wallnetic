import SwiftUI
import WidgetKit

/// Large widget: wallpaper background + clock + date + controls + favorites grid
struct LargeWidgetView: View {
    let entry: WallpaperEntry

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        ZStack {
            // Wallpaper background
            wallpaperBackground

            VStack(spacing: 8) {
                // Top section: Clock + Date
                VStack(spacing: 2) {
                    // Date row
                    HStack(alignment: .firstTextBaseline) {
                        Text(dayNumber)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.pink)

                        Text(monthYear)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))

                        Spacer()
                    }

                    // Clock + day
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(timeString)
                            .font(.system(size: 56, weight: .ultraLight, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 6, y: 3)

                        Text(dayName)
                            .font(.system(size: 24, weight: .light, design: .rounded))
                            .foregroundColor(.white.opacity(0.75))

                        Spacer()
                    }
                }

                // Status bar
                HStack(spacing: 12) {
                    // Playback status
                    HStack(spacing: 4) {
                        Circle()
                            .fill(entry.isPlaying ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(entry.isPlaying ? "Playing" : "Paused")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }

                    Text(entry.currentWallpaper?.name ?? "No Wallpaper")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)

                    Spacer()

                    // Controls
                    HStack(spacing: 10) {
                        Link(destination: URL(string: "wallnetic://playPause")!) {
                            Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.9))
                        }

                        Link(destination: URL(string: "wallnetic://nextWallpaper")!) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial.opacity(0.5))
                    .clipShape(Capsule())
                }

                Divider()
                    .background(Color.white.opacity(0.2))

                // Favorites section
                HStack {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.pink)
                    Text("Favorites")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                }

                if entry.favorites.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "heart.slash")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.3))
                        Text("No favorites yet")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(entry.favorites.prefix(SharedConstants.maxFavorites)) { wallpaper in
                            Link(destination: URL(string: "wallnetic://setWallpaper?id=\(wallpaper.id.uuidString)")!) {
                                favoriteThumbnail(wallpaper)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }

    private func favoriteThumbnail(_ wallpaper: WidgetWallpaperInfo) -> some View {
        ZStack {
            if let image = wallpaper.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.1)
            }

            // Active indicator
            if wallpaper.id == entry.currentWallpaper?.id {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor, lineWidth: 2)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                            .shadow(radius: 2)
                            .padding(3)
                    }
                }
            }
        }
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var wallpaperBackground: some View {
        Group {
            if let image = entry.currentWallpaper?.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .overlay(
                        LinearGradient(
                            colors: [.black.opacity(0.4), .black.opacity(0.1), .black.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blur(radius: 1)
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
