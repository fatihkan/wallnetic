import SwiftUI

// MARK: - Sections

/// The main window's sections, shown as a segmented control in the window
/// toolbar (#343 B2). Explore and Popular became Library's filters and sort
/// order.
enum NavigationTab: String, CaseIterable, Identifiable {
    case home
    case library
    case discover

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .library: return "Library"
        case .discover: return "Discover"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .library: return "square.grid.2x2"
        case .discover: return "globe"
        }
    }
}

// MARK: - Now Playing Bar

/// A bar along the bottom of the main window: the current wallpaper, how it
/// is playing on the displays, and the playback controls from the menu bar.
///
/// On macOS 26 it floats above the content as Liquid Glass, inset from the
/// window edges. On earlier systems it is a full-width bar (#343 B3).
struct NowPlayingBar: View {
    /// The room the bar takes at the bottom of the window, for views that
    /// float just above it.
    static var reservedHeight: CGFloat {
        if #available(macOS 26.0, *) { return 58 + Space.xs }
        return 58
    }

    @EnvironmentObject var wallpaperManager: WallpaperManager
    @ObservedObject private var calm = CalmPlaybackSettings.shared

    private var statuses: [DisplayPlaybackStatus] { wallpaperManager.displayPlaybackStatuses }

    /// "Playing", the first pause reason, or a count across several displays.
    private var summary: String {
        let all = statuses
        guard all.count > 1 else {
            return all.first?.title ?? (wallpaperManager.isPlaying ? "Playing" : "Paused")
        }
        let playing = all.filter { $0.state == .playing }.count
        if playing == all.count { return "Playing on \(all.count) displays" }
        if playing == 0 { return all.first(where: { $0.state != .playing })?.title ?? "Paused" }
        return "Playing on \(playing) of \(all.count) displays"
    }

    /// Each display's own state, for the tooltip. Empty with one display,
    /// where the visible line already says it.
    private var perDisplaySummary: String {
        guard statuses.count > 1 else { return "" }
        return statuses.map { "\($0.displayName): \($0.title)" }.joined(separator: "\n")
    }

    private var canResume: Bool {
        wallpaperManager.isPlaying || !statuses.contains(where: \.blocksResume)
    }

    var body: some View {
        if let wallpaper = wallpaperManager.currentWallpaper {
            if #available(macOS 26.0, *) {
                row(wallpaper)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
                    .padding(.horizontal, Space.sm)
                    .padding(.bottom, Space.xs)
            } else {
                row(wallpaper)
                    .background(.bar)
                    .overlay(alignment: .top) { Divider() }
            }
        }
    }

    private func row(_ wallpaper: Wallpaper) -> some View {
        HStack(spacing: Space.md) {
            AsyncThumbnailView(wallpaper: wallpaper, size: CGSize(width: 56, height: 34), cornerRadius: 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(wallpaper.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(calm.state.isCalmEnabled ? "Calm Mode is on" : summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .help(perDisplaySummary)

            Spacer(minLength: Space.md)

            HStack(spacing: Space.xs) {
                barButton(
                    wallpaperManager.isPlaying ? "Pause" : "Play",
                    icon: wallpaperManager.isPlaying ? "pause.fill" : "play.fill"
                ) {
                    wallpaperManager.togglePlayback()
                }
                .disabled(!canResume)

                barButton("Next Wallpaper", icon: "forward.fill") {
                    wallpaperManager.cycleToNextWallpaper()
                }

                barButton(
                    calm.state.isCalmEnabled ? "Turn Off Calm Mode" : "Turn On Calm Mode",
                    icon: calm.state.isCalmEnabled ? "leaf.fill" : "leaf",
                    isOn: calm.state.isCalmEnabled
                ) {
                    calm.toggleCalmMode()
                }
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
        .frame(maxWidth: .infinity)
    }

    private func barButton(_ label: String, icon: String, isOn: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn ? Color.accentColor : Color.primary)
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Search shortcut

/// ⌘F focuses the toolbar search field. Focusing a `searchable` field from
/// code needs macOS 15; on earlier systems the field is clicked instead.
struct SearchFocusShortcut: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .searchFocused($isFocused)
                .background {
                    Button("Search") { isFocused = true }
                        .keyboardShortcut("f", modifiers: .command)
                        .hidden()
                        .accessibilityHidden(true)
                }
        } else {
            content
        }
    }
}
