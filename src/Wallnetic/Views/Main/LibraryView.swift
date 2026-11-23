import SwiftUI

/// Order of the library when no search is active. Search keeps relevance.
enum LibrarySort: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case oldest = "Oldest"
    case nameAZ = "Name (A–Z)"
    case nameZA = "Name (Z–A)"
    case largest = "Largest"
    case longest = "Longest"

    var id: String { rawValue }

    func apply(to wallpapers: [Wallpaper]) -> [Wallpaper] {
        switch self {
        case .newest: return wallpapers.sorted { $0.dateAdded > $1.dateAdded }
        case .oldest: return wallpapers.sorted { $0.dateAdded < $1.dateAdded }
        case .nameAZ: return wallpapers.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        case .nameZA: return wallpapers.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedDescending }
        case .largest: return wallpapers.sorted { $0.fileSize > $1.fileSize }
        case .longest: return wallpapers.sorted { ($0.duration ?? 0) > ($1.duration ?? 0) }
        }
    }
}

/// The Library section: search, filters, color and sort over the whole
/// library (#343 B2; it absorbed the former Explore and Popular tabs).
struct LibraryView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @Binding var searchText: String

    @State private var selectedCategory: Category = .all
    @State private var hoveredCategory: Category?
    @State private var viewMode: ViewMode = .grid
    @State private var selectedColor: ColorCategory?
    @State private var sort: LibrarySort = .newest

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    enum ViewMode: String {
        case grid, list, carousel3D

        var label: String {
            switch self {
            case .grid: return String(localized: "Grid view")
            case .list: return String(localized: "List view")
            case .carousel3D: return String(localized: "Gallery view")
            }
        }
    }

    /// The filter chips. The case identifies the filter; `title` is what
    /// the chip shows, in the app's language.
    enum Category: String, CaseIterable, Identifiable {
        case all, favorites, recent, long, short, hd, uhd

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return String(localized: "All")
            case .favorites: return String(localized: "Favorites")
            case .recent: return String(localized: "Recent")
            case .long: return String(localized: "Long")
            case .short: return String(localized: "Short")
            case .hd: return "HD" // l10n:ignore
            case .uhd: return "4K" // l10n:ignore
            }
        }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 14)
    ]

    var filteredWallpapers: [Wallpaper] {
        // Keep the search service's relevance ordering when applying filters.
        var result = wallpaperManager.searchWallpapers(query: searchText)

        switch selectedCategory {
        case .all:
            break
        case .favorites:
            result = result.filter { $0.isFavorite }
        case .recent:
            let week = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            result = result.filter { $0.dateAdded > week }
        case .long:
            result = result.filter { ($0.duration ?? 0) > 10 }
        case .short:
            result = result.filter { $0.duration.map { $0 >= 0 && $0 <= 10 } ?? false }
        case .hd:
            result = result.filter { ($0.resolution?.width ?? 0) >= 1920 && ($0.resolution?.width ?? 0) < 3840 }
        case .uhd:
            result = result.filter { ($0.resolution?.width ?? 0) >= 3840 }
        }

        // Color filter
        if let colorFilter = selectedColor {
            result = result.filter { $0.colorCategory == colorFilter }
        }

        return isSearching ? result : sort.apply(to: result)
    }

    var body: some View {
        let results = filteredWallpapers
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Your library" : "Search results")
                        .font(Typo.title1)
                        .tracking(Typo.title1Tracking)
                    Text("Find a wallpaper for your next desktop.")
                        .font(Typo.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selectedCategory != .all || selectedColor != nil || !searchText.isEmpty {
                    Button("Reset filters", action: resetFilters)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, Space.lg)
            .padding(.top, Space.lg)

            // Glass filter bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Category.allCases) { category in
                        filterChip(category)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            // Color swatches
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("Color")
                        .font(Typo.caption)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, Space.xxs)
                    // Clear filter
                    Button {
                        withAnimation(Anim.snappy) { selectedColor = nil }
                    } label: {
                        Text("All")
                            .font(.system(size: 10, weight: selectedColor == nil ? .bold : .medium))
                            .foregroundColor(selectedColor == nil ? .primary : .primary.opacity(0.6))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(selectedColor == nil ? Surface.glassControl.opacity(2.4) : Surface.glassControl)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("All colors")
                    .accessibilityAddTraits(selectedColor == nil ? [.isSelected] : [])

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
                                    Circle().stroke(Color.primary.opacity(selectedColor == cat ? 0.8 : 0.2), lineWidth: selectedColor == cat ? 2 : 0.5)
                                )
                                .scaleEffect(selectedColor == cat ? 1.2 : 1.0)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(cat.rawValue.capitalized)
                        .accessibilityLabel("\(cat.rawValue.capitalized) wallpapers")
                        .accessibilityAddTraits(selectedColor == cat ? [.isSelected] : [])
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
                // One sentence per count, so a translation can place the number.
                let count = Text("\(results.count)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor)
                let label = results.count == 1 ? Text("\(count) wallpaper") : Text("\(count) wallpapers")
                label
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.55))

                Spacer()

                Picker("Sort", selection: $sort) {
                    ForEach(LibrarySort.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .controlSize(.small)
                .disabled(isSearching)
                .help(isSearching ? "Search results are ordered by relevance" : "Sort the library")

                // View mode toggle
                HStack(spacing: 4) {
                    viewModeButton(icon: "square.grid.2x2", mode: .grid)
                    viewModeButton(icon: "list.bullet", mode: .list)
                    viewModeButton(icon: "rectangle.stack", mode: .carousel3D)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            // Content — grid, list, or 3D carousel
            if results.isEmpty {
                noResults
            } else {
                switch viewMode {
                case .grid:
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, wallpaper in
                                ExploreCard(wallpaper: wallpaper, index: index)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 20)
                    }
                case .list:
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, wallpaper in
                                ExploreListRow(wallpaper: wallpaper)
                                    .staggered(index: index)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 20)
                    }
                case .carousel3D:
                    Carousel3DGallery(wallpapers: results) { wallpaper in
                        wallpaperManager.setWallpaper(wallpaper)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    Spacer()
                }
            }
        }
        .background(Color.clear)
        .modifier(KeyPressModifier(
            onLeft: { navigate(in: results, backwards: true) },
            onRight: { navigate(in: results, backwards: false) }
        ))
    }

    private func navigate(in results: [Wallpaper], backwards: Bool) {
        guard let wallpaper = WallpaperBrowsing.adjacent(in: results, currentID: wallpaperManager.currentWallpaper?.id, backwards: backwards) else { return }
        wallpaperManager.setWallpaper(wallpaper)
    }

    private func resetFilters() {
        selectedCategory = .all
        selectedColor = nil
        searchText = ""
    }

    private var noResults: some View {
        VStack(spacing: Space.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No matching wallpapers")
                .font(Typo.title2)
            Text("Try a different search, or clear the filters to see your library.")
                .font(Typo.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Show all wallpapers", action: resetFilters)
                .buttonStyle(.bordered)
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - View Mode Button

    private func viewModeButton(icon: String, mode: ViewMode) -> some View {
        Button {
            withAnimation(Anim.snappy) { viewMode = mode }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(viewMode == mode ? .primary : .primary.opacity(0.45))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(viewMode == mode ? Surface.glassControl.opacity(2.0) : .clear)
                )
        }
        .buttonStyle(.plain)
        .help(mode.label)
        .accessibilityLabel(mode.label)
        .accessibilityAddTraits(viewMode == mode ? [.isSelected] : [])
    }

    // MARK: - Filter Chip

    @ViewBuilder
    private func filterChip(_ category: Category) -> some View {
        let isSelected = selectedCategory == category
        let isHovered = hoveredCategory == category

        Button {
            withAnimation(.spring(response: Anim.enter, dampingFraction: 0.8)) {
                selectedCategory = category
            }
        } label: {
            Text(category.title)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .primary : .primary.opacity(isHovered ? 0.85 : 0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    ZStack {
                        if isSelected {
                            Capsule().fill(Color.accentColor.opacity(0.25))
                            Capsule().stroke(Color.accentColor.opacity(0.4), lineWidth: 0.5)
                        } else if isHovered {
                            Capsule().fill(Surface.glassControl.opacity(1.5))
                        } else {
                            Capsule().fill(Surface.glassControl)
                            Capsule().stroke(Surface.hairline, lineWidth: 0.5)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
    @State private var isLoadingThumbnail = true
    @State private var isHovering = false
    @State private var renamingWallpaper: Wallpaper?
    @State private var previewingWallpaper: Wallpaper?
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                wallpaperManager.setWallpaper(wallpaper)
            } label: {
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
                                        .fill(Surface.glassControl)
                                        .overlay {
                                            if isLoadingThumbnail {
                                                ProgressView().controlSize(.small)
                                            } else {
                                                Image(systemName: "film").foregroundStyle(.secondary)
                                            }
                                        }
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
                .cardHighlight(isHovering: isHovering, cornerRadius: 10)
                .scaleEffect(isHovering ? 1.03 : 1.0)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Set \(wallpaper.displayName) as wallpaper")
            .help("Set as wallpaper")

            VStack(alignment: .leading, spacing: 2) {
                Text(wallpaper.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary.opacity(isHovering ? 0.95 : 0.8))
                    .lineLimit(2)
                    .truncationMode(.tail)

                Text("\(wallpaper.formattedResolution) \u{2022} \(wallpaper.formattedFileSize)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.5))
            }
        }
        .animation(.spring(response: Anim.enter, dampingFraction: 0.75), value: isHovering)
        .onHover { h in isHovering = h }
        .staggered(index: index)
        .contextMenu {
            WallpaperContextMenu(wallpaper: wallpaper, onPreview: { previewingWallpaper = wallpaper }, onRename: {
                renameText = wallpaper.displayName
                renamingWallpaper = wallpaper
            })
        }
        .sheet(item: $previewingWallpaper) { WallpaperPreviewSheet(wallpaper: $0) }
        .sheet(item: $renamingWallpaper) { wp in
            RenameWallpaperSheet(wallpaper: wp, title: $renameText, onSave: { newTitle in
                wallpaperManager.renameWallpaper(wp, to: newTitle)
                renamingWallpaper = nil
            }, onCancel: { renamingWallpaper = nil })
        }
        .task {
            thumbnail = await wallpaper.generateThumbnail()?.image
            isLoadingThumbnail = false
        }
    }
}

// MARK: - Explore List Row

struct ExploreListRow: View {
    let wallpaper: Wallpaper
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var thumbnail: NSImage?
    @State private var isLoadingThumbnail = true
    @State private var isHovering = false
    @State private var previewingWallpaper: Wallpaper?

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
                    .fill(Surface.glassControl)
                    .frame(width: 80, height: 45)
                    .overlay {
                        if isLoadingThumbnail {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "film").foregroundStyle(.secondary)
                        }
                    }
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(wallpaper.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary.opacity(0.95))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(wallpaper.formattedResolution)
                    Text(wallpaper.formattedDuration)
                    Text(wallpaper.formattedFileSize)
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary.opacity(0.55))
            }

            Spacer()

            // Favorite
            if wallpaper.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.pink)
            }

            // Keep the action available to keyboard and VoiceOver users.
            Group {
                Button {
                    wallpaperManager.setWallpaper(wallpaper)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.85))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Surface.glassControl.opacity(1.5)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Set \(wallpaper.displayName) as wallpaper")
                .help("Set as wallpaper")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Surface.glassControl : Color.clear)
        )
        .onHover { h in withAnimation(Anim.hover) { isHovering = h } }
        .onTapGesture(count: 2) { wallpaperManager.setWallpaper(wallpaper) }
        .contextMenu {
            WallpaperContextMenu(wallpaper: wallpaper, onPreview: { previewingWallpaper = wallpaper })
        }
        .sheet(item: $previewingWallpaper) { WallpaperPreviewSheet(wallpaper: $0) }
        .task {
            thumbnail = await wallpaper.generateThumbnail(size: CGSize(width: 160, height: 90))?.image
            isLoadingThumbnail = false
        }
    }
}
