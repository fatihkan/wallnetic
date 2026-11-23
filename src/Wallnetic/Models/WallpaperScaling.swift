import Foundation

/// How a wallpaper's video is placed on a display whose shape differs from
/// the video's (#348).
enum WallpaperScaling: String, Codable, CaseIterable, Identifiable {
    /// Cover the display and crop what does not fit. The default.
    case fill
    /// Show the whole frame, over a blurred and dimmed copy of the same
    /// frame that covers the display. Nothing is cropped.
    case fitBlurred

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: return "Fill"
        case .fitBlurred: return "Fit with Blurred Backdrop"
        }
    }
}
