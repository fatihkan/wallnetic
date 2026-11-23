import SwiftUI

// DUSUK-2: scoped to HomeView so it can't accidentally be reused as
// app-wide. Access via `HomeView.horizontalInset`.
extension HomeView {
    /// The same page margin as Library, so content does not shift sideways
    /// when the tab changes.
    static let horizontalInset: CGFloat = Space.lg
}
private var homeHorizontalInset: CGFloat { HomeView.horizontalInset }

/// Home starts from the user's own desktop: what each display shows now,
/// then recently used wallpapers, favourites, recent additions and the whole
/// library (#343 B2). It replaced an auto-rotating hero banner; the rules
/// are in `HomeSections`.
struct HomeView: View {
    /// Shows the Library tab, for a display that has no wallpaper yet.
    var onOpenLibrary: () -> Void = {}
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var screens: [NSScreen] = NSScreen.screens

    private var sections: HomeSections {
        HomeSections.make(
            wallpapers: wallpaperManager.wallpapers,
            displays: wallpaperManager.displayPlaybackStatuses,
            wallpaperForDisplay: { displayID in
                screens.first { $0.displayID == displayID }
                    .flatMap { wallpaperManager.wallpaper(for: $0)?.id }
            },
            recentlyUsedPaths: wallpaperManager.recentlyUsedPaths
        )
    }

    var body: some View {
        let sections = sections
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                if !sections.desktop.isEmpty {
                    DesktopNowSection(items: sections.desktop, onOpenLibrary: onOpenLibrary)
                }

                if !sections.recentlyUsed.isEmpty {
                    CarouselSection(
                        title: "Recently Used",
                        icon: "clock.arrow.circlepath",
                        iconColor: .teal,
                        wallpapers: sections.recentlyUsed
                    )
                }

                if !sections.favorites.isEmpty {
                    CarouselSection(
                        title: "Favorites",
                        icon: "heart.fill",
                        iconColor: .pink,
                        wallpapers: sections.favorites
                    )
                }

                if !sections.recent.isEmpty {
                    CarouselSection(
                        title: "Recently Added",
                        icon: "sparkles",
                        iconColor: .yellow,
                        wallpapers: sections.recent
                    )
                }

                if !sections.all.isEmpty {
                    CarouselSection(
                        title: "All Wallpapers",
                        icon: "square.grid.2x2.fill",
                        iconColor: .blue,
                        wallpapers: sections.all
                    )
                }

                Spacer(minLength: 40)
            }
            .padding(.top, 24)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
        }
    }
}

// MARK: - On your desktop now

/// One tile per display: its wallpaper, its name, how it is playing and,
/// when the display needs attention, the control that fixes it.
struct DesktopNowSection: View {
    let items: [HomeSections.DesktopItem]
    var onOpenLibrary: () -> Void = {}
    @EnvironmentObject var wallpaperManager: WallpaperManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("On your desktop now")
                    .font(Typo.title1)
                    .tracking(Typo.title1Tracking)
                Text(items.count == 1 ? "What your display is showing." : "What each display is showing.")
                    .font(Typo.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, homeHorizontalInset)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(items) { item in
                        DesktopTile(
                            item: item,
                            wallpaper: item.wallpaperID.flatMap { id in
                                wallpaperManager.wallpapers.first { $0.id == id }
                            },
                            onRetry: { wallpaperManager.retryWallpaper(on: item.id) },
                            onOpenLibrary: onOpenLibrary
                        )
                    }
                }
                .padding(.horizontal, homeHorizontalInset)
                .padding(.vertical, 4)
            }
        }
    }
}

private struct DesktopTile: View {
    let item: HomeSections.DesktopItem
    let wallpaper: Wallpaper?
    let onRetry: () -> Void
    let onOpenLibrary: () -> Void

    private let size = CGSize(width: 320, height: 200)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                if let wallpaper {
                    AsyncThumbnailView(wallpaper: wallpaper, size: size, cornerRadius: 12)
                } else {
                    Image(systemName: "display")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(wallpaper?.displayName ?? "No wallpaper")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Image(systemName: item.statusSymbol)
                        Text("\(item.displayName) · \(item.statusTitle)")
                            .lineLimit(1)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint(item.statusDetail)

                Spacer(minLength: 0)

                // One control, and only when this display needs it. Play,
                // Next and Calm Mode act on every display and are in the
                // now-playing bar.
                if item.canRetry {
                    Button("Retry", action: onRetry)
                        .controlSize(.small)
                        .accessibilityLabel("Retry wallpaper on \(item.displayName)")
                } else if wallpaper == nil {
                    Button("Open Library", action: onOpenLibrary)
                        .controlSize(.small)
                        .accessibilityLabel("Open Library to choose a wallpaper for \(item.displayName)")
                }
            }
            .frame(width: size.width, alignment: .leading)
        }
        .help(item.statusDetail)
    }
}

// MARK: - Carousel Section

struct CarouselSection: View {
    let title: String
    let icon: String
    let iconColor: Color
    let wallpapers: [Wallpaper]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(iconColor)

                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)

                Text("\(wallpapers.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.4))
            }
            .padding(.horizontal, homeHorizontalInset)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(Array(wallpapers.enumerated()), id: \.element.id) { index, wallpaper in
                        CarouselCard(wallpaper: wallpaper, allowsTrim: true)
                            .staggered(index: index)
                    }
                }
                .padding(.horizontal, homeHorizontalInset)
                .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - Carousel Card with Glow

struct CarouselCard: View {
    let wallpaper: Wallpaper
    var onApply: ((Wallpaper) -> Void)? = nil
    /// Trim is offered on Home's carousel, not in Explore's 3D carousel,
    /// which shares this card.
    var allowsTrim = false
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var thumbnail: NSImage?
    @State private var isLoadingThumbnail = true
    @State private var isHovering = false
    @State private var optimizingWallpaper: Wallpaper?
    @State private var trimmingWallpaper: Wallpaper?
    @State private var renamingWallpaper: Wallpaper?
    @State private var previewingWallpaper: Wallpaper?
    @State private var renameText = ""
    @State private var pointer = CGPoint(x: 0.5, y: 0.5)
    @State private var lastPointerWrite: TimeInterval = 0
    private static let pointerThrottle: TimeInterval = 1.0 / 30.0  // P1-7

    private let cardWidth: CGFloat = 240
    private let cardHeight: CGFloat = 135

    /// Subtle magnetic tilt: pointer's offset from center drives a ±6°
    /// rotation around the y/x axes plus a 2-3px translation. Falls back
    /// to flat when not hovering.
    private var tiltX: Double {
        guard isHovering && !reduceMotion else { return 0 }
        return Double(0.5 - pointer.y) * 8  // top → tilt forward
    }

    private var tiltY: Double {
        guard isHovering && !reduceMotion else { return 0 }
        return Double(pointer.x - 0.5) * 8  // right → tilt right
    }

    /// The duration arrives a moment after launch. `Wallpaper` equality
    /// leaves it out, so SwiftUI keeps the copy this card was created with;
    /// read the library's current copy instead.
    private var durationText: String {
        (wallpaperManager.wallpapers.first { $0.id == wallpaper.id } ?? wallpaper).formattedDuration
    }

    private var glareOffset: CGFloat {
        min(1, max(0, pointer.x))
    }

    /// Specular intensity scales with tilt magnitude — like a real lens
    /// reflecting more light when angled.
    private var specularIntensity: Double {
        guard isHovering && !reduceMotion else { return 0 }
        let mag = sqrt(tiltX * tiltX + tiltY * tiltY)
        return min(0.22, 0.06 + mag / 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if let onApply { onApply(wallpaper) }
                else { wallpaperManager.setWallpaper(wallpaper) }
            } label: {
                ZStack(alignment: .bottom) {
                    // Thumbnail
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
                    .frame(width: cardWidth, height: cardHeight)
                    .clipped()

                    // Hover overlay — image content always dark, so keep
                    // contrast overlay dark (not theme-aware) for legibility
                    // of the play icon over thumbnails.
                    if isHovering {
                        Color.black.opacity(0.35)

                        Image(systemName: "play.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.95))

                        VStack {
                            Spacer()
                            LinearGradient(colors: [.clear, .black.opacity(0.8)],
                                           startPoint: .top, endPoint: .bottom)
                                .frame(height: 50)
                        }
                    }

                    // Duration badge — over thumbnail image, stays dark for contrast
                    VStack {
                        HStack {
                            Spacer()
                            Text(durationText)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(Color.black.opacity(0.6))
                                )
                                .padding(6)
                        }
                        Spacer()
                    }

                    // Active indicator
                    if wallpaper.id == wallpaperManager.currentWallpaper?.id {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor, lineWidth: 2)
                    }
                }
                .frame(width: cardWidth, height: cardHeight)
                .overlay(
                    // Specular highlight — follows pointer, intensifies with
                    // tilt magnitude. The gradient angle subtly tracks the
                    // y-axis rotation so it looks like a real light source
                    // staying overhead as the card tilts.
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0), location: max(0, glareOffset - 0.28)),
                            .init(color: .white.opacity(specularIntensity), location: glareOffset),
                            .init(color: .white.opacity(0), location: min(1, glareOffset + 0.28))
                        ],
                        startPoint: UnitPoint(x: 0.5 - tiltY / 50, y: 0),
                        endPoint: UnitPoint(x: 0.5 + tiltY / 50, y: 1)
                    )
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                )
                .cardHighlight(isHovering: isHovering, cornerRadius: 8)
                .rotation3DEffect(.degrees(tiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.7)
                .rotation3DEffect(.degrees(tiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
                .scaleEffect(isHovering && !reduceMotion ? 1.04 : 1.0)
                .background(
                    // Trackpad/mouse position tracker (overlay placed in front of the card for hit testing)
                    GeometryReader { proxy in
                        Color.clear.contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let loc):
                                    guard !reduceMotion, proxy.size.width > 0, proxy.size.height > 0 else { return }
                                    let now = CACurrentMediaTime()
                                    guard now - lastPointerWrite >= Self.pointerThrottle else { return }
                                    lastPointerWrite = now
                                    pointer = CGPoint(
                                        x: min(max(loc.x / proxy.size.width, 0), 1),
                                        y: min(max(loc.y / proxy.size.height, 0), 1)
                                    )
                                case .ended:
                                    pointer = CGPoint(x: 0.5, y: 0.5)
                                }
                            }
                    }
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Set \(wallpaper.displayName) as wallpaper")
            .accessibilityAddTraits(wallpaper.id == wallpaperManager.currentWallpaper?.id ? [.isSelected] : [])
            .help("Set as wallpaper")

            Text(wallpaper.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary.opacity(isHovering ? 0.95 : 0.75))
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(width: cardWidth, alignment: .leading)
        }
        .animation(reduceMotion ? nil : .spring(response: Anim.enter, dampingFraction: 0.75), value: isHovering)
        .onHover { h in isHovering = h }
        .contextMenu {
            WallpaperContextMenu(wallpaper: wallpaper, onPreview: { previewingWallpaper = wallpaper },
                                 onOptimize: { optimizingWallpaper = wallpaper },
                                 onTrim: allowsTrim ? { trimmingWallpaper = wallpaper } : nil, onRename: {
                renameText = wallpaper.displayName
                renamingWallpaper = wallpaper
            })
        }
        .sheet(item: $optimizingWallpaper) { VideoOptimizationSheet(wallpaper: $0) }
        .sheet(item: $previewingWallpaper) { WallpaperPreviewSheet(wallpaper: $0) }
        .sheet(item: $trimmingWallpaper) { VideoTrimSheet(wallpaper: $0) }
        .sheet(item: $renamingWallpaper) { wp in
            RenameWallpaperSheet(wallpaper: wp, title: $renameText, onSave: { newTitle in
                wallpaperManager.renameWallpaper(wp, to: newTitle)
                renamingWallpaper = nil
            }, onCancel: { renamingWallpaper = nil })
        }
        .task(id: wallpaper.id) {
            thumbnail = nil
            isLoadingThumbnail = true
            let image = await wallpaper.generateThumbnail(size: CGSize(width: 480, height: 270))?.image
            guard !Task.isCancelled else { return }
            thumbnail = image
            isLoadingThumbnail = false
        }
    }
}
