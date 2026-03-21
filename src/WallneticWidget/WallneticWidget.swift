import WidgetKit
import SwiftUI

struct WallneticWidget: Widget {
    let kind: String = "WallneticWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WallpaperTimelineProvider()) { entry in
            if #available(macOS 14.0, *) {
                WallneticWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                WallneticWidgetEntryView(entry: entry)
                    .padding()
                    .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .configurationDisplayName("Wallnetic")
        .description("Control your live wallpapers")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct WallneticWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: WallpaperTimelineProvider.Entry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

@available(macOS 14.0, *)
#Preview(as: .systemSmall) {
    WallneticWidget()
} timeline: {
    WallpaperEntry(date: .now, currentWallpaper: nil, isPlaying: false, favorites: [])
}

@available(macOS 14.0, *)
#Preview(as: .systemMedium) {
    WallneticWidget()
} timeline: {
    WallpaperEntry(date: .now, currentWallpaper: nil, isPlaying: true, favorites: [])
}
