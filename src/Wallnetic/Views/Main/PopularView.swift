import SwiftUI

/// Popular tab with ranked cards and neon glow effects
struct PopularView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager

    enum SortOption: String, CaseIterable {
        case newest = "Newest"
        case oldest = "Oldest"
        case nameAZ = "Name A-Z"
        case nameZA = "Name Z-A"
        case largest = "Largest"
        case longest = "Longest"
    }

    @State private var sortOption: SortOption = .newest

    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 16)
    ]

    var sortedWallpapers: [Wallpaper] {
        switch sortOption {
        case .newest: return wallpaperManager.wallpapers.sorted { $0.dateAdded > $1.dateAdded }
        case .oldest: return wallpaperManager.wallpapers.sorted { $0.dateAdded < $1.dateAdded }
        case .nameAZ: return wallpaperManager.wallpapers.sorted { $0.name < $1.name }
        case .nameZA: return wallpaperManager.wallpapers.sorted { $0.name > $1.name }
        case .largest: return wallpaperManager.wallpapers.sorted { $0.fileSize > $1.fileSize }
        case .longest: return wallpaperManager.wallpapers.sorted { ($0.duration ?? 0) > ($1.duration ?? 0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                        .neonGlow(.orange, isActive: true, radius: 6)
                    Text("Popular")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))

                    Picker("", selection: $sortOption) {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .frame(width: 100)
                }

                Text("\(sortedWallpapers.count)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor)
                +
                Text(" wallpapers")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.orange.opacity(0.1), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 0.5)

            // Grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(sortedWallpapers.enumerated()), id: \.element.id) { index, wallpaper in
                        PopularCard(wallpaper: wallpaper, rank: index + 1)
                            .staggered(index: index)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
        }
        .background(Color.clear)
    }
}

// MARK: - Popular Card with Glow

struct PopularCard: View {
    let wallpaper: Wallpaper
    let rank: Int
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var thumbnail: NSImage?
    @State private var isHovering = false
    @State private var renamingWallpaper: Wallpaper?
    @State private var renameText = ""

    private var rankColor: Color {
        switch rank {
        case 1: return .orange
        case 2: return Color(red: 0.85, green: 0.65, blue: 0.1)
        case 3: return Color(red: 0.7, green: 0.45, blue: 0.15)
        default: return .white.opacity(0.4)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                // Fixed 16:9 container - image fills and clips
                Color.clear
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay(
                        Group {
                            if let thumbnail = thumbnail {
                                Image(nsImage: thumbnail)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Rectangle()
                                    .fill(Color.white.opacity(0.03))
                                    .overlay { ProgressView().scaleEffect(0.6) }
                            }
                        }
                    )
                    .clipped()

                // Rank badge with glow
                Text("#\(rank)")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(rank <= 3 ? .black : .white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(rankColor)
                    )
                    .neonGlow(rankColor, isActive: rank <= 3, radius: 6)
                    .padding(8)

                // Hover overlay - centered
                if isHovering {
                    ZStack {
                        Color.black.opacity(0.25)
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .transition(.opacity)
                }
            }
            .glowCard(isHovering: isHovering, cornerRadius: 10, glowColor: rank <= 3 ? rankColor : .accentColor)
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .onTapGesture(count: 2) {
                wallpaperManager.setWallpaper(wallpaper)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(wallpaper.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(isHovering ? 0.95 : 0.75))
                        .lineLimit(2)
                        .truncationMode(.tail)

                    Text("\(wallpaper.formattedResolution) \u{2022} \(wallpaper.formattedDuration)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                }

                Spacer()

                if wallpaper.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.pink)
                        .neonGlow(.pink, isActive: true, radius: 4)
                }
            }
        }
        .animation(.spring(response: Anim.enter, dampingFraction: 0.75), value: isHovering)
        .onHover { h in isHovering = h }
        .contextMenu {
            Button { wallpaperManager.setWallpaper(wallpaper) } label: {
                Label("Set as Wallpaper", systemImage: "photo.on.rectangle")
            }
            Button { wallpaperManager.toggleFavorite(wallpaper) } label: {
                Label(wallpaper.isFavorite ? "Remove Favorite" : "Add Favorite",
                      systemImage: wallpaper.isFavorite ? "heart.fill" : "heart")
            }
            Button {
                renameText = wallpaper.displayName
                renamingWallpaper = wallpaper
            } label: {
                Label("Rename", systemImage: "pencil")
            }
        }
        .sheet(item: $renamingWallpaper) { wp in
            RenameWallpaperSheet(wallpaper: wp, title: $renameText, onSave: { newTitle in
                wallpaperManager.renameWallpaper(wp, to: newTitle)
                renamingWallpaper = nil
            }, onCancel: { renamingWallpaper = nil })
        }
        .task { thumbnail = await wallpaper.generateThumbnail() }
    }
}
