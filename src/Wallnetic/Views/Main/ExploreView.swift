import SwiftUI

/// Explore tab with glass filter chips and glow cards
struct ExploreView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    let searchText: String

    @State private var selectedCategory: String = "All"
    @State private var hoveredCategory: String?
    @State private var viewMode: ViewMode = .grid
    @State private var selectedColor: ColorCategory?

    enum ViewMode: String {
        case grid, list
    }

    private let categories = ["All", "Favorites", "Recent", "Long", "Short", "HD", "4K"]

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 14)
    ]

    var filteredWallpapers: [Wallpaper] {
        var result = wallpaperManager.wallpapers

        switch selectedCategory {
        case "Favorites":
            result = result.filter { $0.isFavorite }
        case "Recent":
            let week = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            result = result.filter { $0.dateAdded > week }
        case "Long":
            result = result.filter { ($0.duration ?? 0) > 10 }
        case "Short":
            result = result.filter { ($0.duration ?? 0) <= 10 }
        case "HD":
            result = result.filter { ($0.resolution?.width ?? 0) >= 1920 && ($0.resolution?.width ?? 0) < 3840 }
        case "4K":
            result = result.filter { ($0.resolution?.width ?? 0) >= 3840 }
        default:
            break
        }

        // Color filter
        if let colorFilter = selectedColor {
            result = result.filter { $0.colorCategory == colorFilter }
        }

        if !searchText.isEmpty {
            let fuzzyResults = wallpaperManager.searchWallpapers(query: searchText)
            let fuzzyIDs = Set(fuzzyResults.map { $0.id })
            result = result.filter { fuzzyIDs.contains($0.id) }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Glass filter bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(categories, id: \.self) { category in
                        filterChip(category)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            // Color swatches
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // Clear filter
                    Button {
                        withAnimation(Anim.snappy) { selectedColor = nil }
                    } label: {
                        Text("All")
                            .font(.system(size: 10, weight: selectedColor == nil ? .bold : .medium))
                            .foregroundColor(selectedColor == nil ? .white : .white.opacity(0.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(selectedColor == nil ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
                            )
                    }
                    .buttonStyle(.plain)

                    ForEach(ColorCategory.allCases) { cat in
                        Button {
                            withAnimation(Anim.snappy) {
                                selectedColor = selectedColor == cat ? nil : cat
                            }
                        } label: {
                            Circle()
                                .fill(cat.color)
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Circle().stroke(.white.opacity(selectedColor == cat ? 0.8 : 0.15), lineWidth: selectedColor == cat ? 2 : 0.5)
                                )
                                .scaleEffect(selectedColor == cat ? 1.2 : 1.0)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            // Subtle divider with glow
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.accentColor.opacity(0.15), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 0.5)

            // Results count + view mode toggle
            HStack {
                Text("\(filteredWallpapers.count)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor)
                +
                Text(" wallpapers")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))

                Spacer()

                // View mode toggle
                HStack(spacing: 4) {
                    viewModeButton(icon: "square.grid.2x2", mode: .grid)
                    viewModeButton(icon: "list.bullet", mode: .list)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            // Content — grid or list
            ScrollView {
                if viewMode == .grid {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Array(filteredWallpapers.enumerated()), id: \.element.id) { index, wallpaper in
                            ExploreCard(wallpaper: wallpaper, index: index)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 20)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(filteredWallpapers.enumerated()), id: \.element.id) { index, wallpaper in
                            ExploreListRow(wallpaper: wallpaper)
                                .staggered(index: index)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(Color.clear)
        .modifier(KeyPressModifier(
            onLeft: {
                let wallpapers = filteredWallpapers
                guard !wallpapers.isEmpty else { return }
                wallpaperManager.cycleToNextWallpaper()
            },
            onRight: {
                wallpaperManager.cycleToNextWallpaper()
            }
        ))
    }

    // MARK: - View Mode Button

    private func viewModeButton(icon: String, mode: ViewMode) -> some View {
        Button {
            withAnimation(Anim.snappy) { viewMode = mode }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(viewMode == mode ? .white : .white.opacity(0.3))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(viewMode == mode ? Color.white.opacity(0.1) : .clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filter Chip

    @ViewBuilder
    private func filterChip(_ category: String) -> some View {
        let isSelected = selectedCategory == category
        let isHovered = hoveredCategory == category

        Button {
            withAnimation(.spring(response: Anim.enter, dampingFraction: 0.8)) {
                selectedCategory = category
            }
        } label: {
            Text(category)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(isHovered ? 0.8 : 0.6))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    ZStack {
                        if isSelected {
                            Capsule().fill(Color.accentColor.opacity(0.25))
                            Capsule().stroke(Color.accentColor.opacity(0.4), lineWidth: 0.5)
                        } else if isHovered {
                            Capsule().fill(Color.white.opacity(0.06))
                        } else {
                            Capsule().fill(Color.white.opacity(0.03))
                            Capsule().stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                        }
                    }
                )
                .neonGlow(.accentColor, isActive: isSelected, radius: 6)
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: Anim.micro)) { hoveredCategory = h ? category : nil }
        }
    }
}

// MARK: - Explore Card with Glow

struct ExploreCard: View {
    let wallpaper: Wallpaper
    let index: Int
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var thumbnail: NSImage?
    @State private var isHovering = false
    @State private var renamingWallpaper: Wallpaper?
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
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

                // Badges
                VStack {
                    HStack {
                        if wallpaper.isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                                .padding(5)
                                .background(
                                    Circle()
                                        .fill(.pink.opacity(0.8))
                                )
                                .neonGlow(.pink, isActive: true, radius: 4)
                                .padding(6)
                        }
                        Spacer()
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        Text(wallpaper.formattedDuration)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.black.opacity(0.6)))
                            .padding(6)
                    }
                }

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
            .glowCard(isHovering: isHovering, cornerRadius: 10)
            .scaleEffect(isHovering ? 1.03 : 1.0)
            .onTapGesture(count: 2) {
                wallpaperManager.setWallpaper(wallpaper)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(wallpaper.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(isHovering ? 0.95 : 0.75))
                    .lineLimit(2)
                    .truncationMode(.tail)

                Text("\(wallpaper.formattedResolution) \u{2022} \(wallpaper.formattedFileSize)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
        .animation(.spring(response: Anim.enter, dampingFraction: 0.75), value: isHovering)
        .onHover { h in isHovering = h }
        .staggered(index: index)
        .contextMenu {
            WallpaperContextMenu(wallpaper: wallpaper, onRename: {
                renameText = wallpaper.displayName
                renamingWallpaper = wallpaper
            })
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

// MARK: - Explore List Row

struct ExploreListRow: View {
    let wallpaper: Wallpaper
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var thumbnail: NSImage?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let thumb = thumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 45)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 80, height: 45)
                    .overlay { ProgressView().scaleEffect(0.5) }
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(wallpaper.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(wallpaper.formattedResolution)
                    Text(wallpaper.formattedDuration)
                    Text(wallpaper.formattedFileSize)
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
            }

            Spacer()

            // Favorite
            if wallpaper.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.pink)
            }

            // Apply button on hover
            if isHovering {
                Button {
                    wallpaperManager.setWallpaper(wallpaper)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.white.opacity(0.04) : .clear)
        )
        .onHover { h in withAnimation(Anim.hover) { isHovering = h } }
        .onTapGesture(count: 2) { wallpaperManager.setWallpaper(wallpaper) }
        .contextMenu {
            WallpaperContextMenu(wallpaper: wallpaper)
        }
        .task { thumbnail = await wallpaper.generateThumbnail(size: CGSize(width: 160, height: 90)) }
    }
}
