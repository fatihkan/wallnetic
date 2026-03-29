import SwiftUI
import WidgetKit

/// Large widget: wallpaper bg + clock + date + glass controls + favorites grid
struct LargeWidgetView: View {
    let entry: WallpaperEntry

    private let columns = [
        GridItem(.flexible(), spacing: 5),
        GridItem(.flexible(), spacing: 5),
        GridItem(.flexible(), spacing: 5)
    ]

    var body: some View {
        ZStack {
            wallpaperBackground

            VStack(spacing: 6) {
                // Date row
                HStack(alignment: .center) {
                    Text(dayNumber)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.pink, .pink.opacity(0.7)],
                                           startPoint: .top, endPoint: .bottom)
                        )

                    Text(monthYear)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))

                    Spacer()
                }

                // Clock + day
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(timeString)
                        .font(.system(size: 58, weight: .ultraLight, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 10, y: 3)
                        .tracking(1)

                    Text(dayName)
                        .font(.system(size: 22, weight: .light, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))

                    Spacer()
                }
                .padding(.top, -6)

                // Status + controls glass bar
                HStack(spacing: 8) {
                    Circle()
                        .fill(entry.isPlaying ? Color.green : Color.orange)
                        .frame(width: 5, height: 5)

                    Text(entry.currentWallpaper?.name ?? "No Wallpaper")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)

                    Spacer()

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
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial.opacity(0.6))
                            .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
                    )
                }

                // Divider
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 0.5)
                    .padding(.vertical, 2)

                // Favorites header
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.pink.opacity(0.8))
                    Text("FAVORITES")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                        .tracking(1.5)
                    Spacer()
                }

                // Favorites grid or empty
                if entry.favorites.isEmpty {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "heart.slash")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.2))
                        Text("No favorites yet")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    Spacer()
                } else {
                    LazyVGrid(columns: columns, spacing: 5) {
                        ForEach(entry.favorites.prefix(SharedConstants.maxFavorites)) { wallpaper in
                            Link(destination: URL(string: "wallnetic://setWallpaper?id=\(wallpaper.id.uuidString)")!) {
                                favoriteTile(wallpaper)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(14)
        }
        .clipShape(ContainerRelativeShape())
    }

    private func favoriteTile(_ wallpaper: WidgetWallpaperInfo) -> some View {
        ZStack {
            if let image = wallpaper.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.08)
            }

            if wallpaper.id == entry.currentWallpaper?.id {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.pink.opacity(0.7), lineWidth: 1.5)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.pink)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                            .padding(3)
                    }
                }
            }
        }
        .frame(height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        )
    }

    private var wallpaperBackground: some View {
        Group {
            if let image = entry.currentWallpaper?.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 2)
                    .overlay(
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(0.45), location: 0),
                                .init(color: .black.opacity(0.1), location: 0.35),
                                .init(color: .black.opacity(0.5), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else {
                ZStack {
                    Color(red: 0.06, green: 0.06, blue: 0.12)
                    LinearGradient(
                        colors: [.purple.opacity(0.25), .blue.opacity(0.15)],
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
