import Foundation

/// What Home shows, worked out from the library and the displays (#343 B2).
///
/// Home starts from the user's own desktop, what each display is showing now,
/// then favourites, recent additions and the whole library. It replaced an
/// auto-rotating hero banner. The rules live here, apart from the view, so
/// they are unit-tested.
struct HomeSections: Equatable {
    /// One display and what it shows.
    struct DesktopItem: Identifiable, Equatable {
        /// The display's `CGDirectDisplayID`.
        let id: UInt32
        let displayName: String
        /// The wallpaper on this display, or nil when it has none or the
        /// wallpaper is no longer in the library.
        let wallpaperID: UUID?
        let statusTitle: String
        let statusSymbol: String
    }

    let desktop: [DesktopItem]
    let favorites: [Wallpaper]
    let recent: [Wallpaper]
    let all: [Wallpaper]

    /// Wallpapers added within this window count as recent.
    static let recentWindow: TimeInterval = 7 * 24 * 60 * 60

    /// "All Wallpapers" repeats the library, so it appears only once the
    /// library holds more than a handful of videos.
    static let minimumForAllRow = 4

    static func make(
        wallpapers: [Wallpaper],
        displays: [DisplayPlaybackStatus],
        wallpaperForDisplay: (UInt32) -> UUID?,
        now: Date = Date()
    ) -> HomeSections {
        let known = Set(wallpapers.map(\.id))
        let desktop = displays.map { status -> DesktopItem in
            let assigned = wallpaperForDisplay(status.id).flatMap { known.contains($0) ? $0 : nil }
            return DesktopItem(
                id: status.id,
                displayName: status.displayName,
                wallpaperID: assigned,
                statusTitle: status.title,
                statusSymbol: status.symbol
            )
        }

        let cutoff = now.addingTimeInterval(-recentWindow)
        return HomeSections(
            desktop: desktop,
            favorites: wallpapers.filter(\.isFavorite),
            recent: wallpapers
                .filter { $0.dateAdded > cutoff }
                .sorted { $0.dateAdded > $1.dateAdded },
            all: wallpapers.count >= minimumForAllRow ? wallpapers : []
        )
    }
}
