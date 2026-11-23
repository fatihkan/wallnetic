import CoreGraphics

/// Sizes for the wallpaper preview (#349).
enum WallpaperPreviewLayout {
    /// The stage a wallpaper is previewed on: the display's shape, as large
    /// as fits in `bounds`. Never larger than `bounds` on either side.
    static func stageSize(displaySize: CGSize, fitting bounds: CGSize) -> CGSize {
        guard displaySize.width > 0, displaySize.height > 0,
              bounds.width > 0, bounds.height > 0 else { return bounds }
        let scale = min(bounds.width / displaySize.width, bounds.height / displaySize.height)
        return CGSize(width: (displaySize.width * scale).rounded(), height: (displaySize.height * scale).rounded())
    }

    /// The part of a display that is not under the menu bar or the Dock, as
    /// fractions of the display (origin bottom-left, 0...1). The Desktop
    /// Clock is placed inside it, on the desktop and in the preview.
    static func visibleFraction(screenFrame: CGRect, visibleFrame: CGRect) -> CGRect {
        guard screenFrame.width > 0, screenFrame.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        return CGRect(x: (visibleFrame.minX - screenFrame.minX) / screenFrame.width,
                      y: (visibleFrame.minY - screenFrame.minY) / screenFrame.height,
                      width: visibleFrame.width / screenFrame.width,
                      height: visibleFrame.height / screenFrame.height)
    }

    /// `fraction` of a stage of `size`, in the stage's coordinates.
    static func rect(_ fraction: CGRect, in size: CGSize) -> CGRect {
        CGRect(x: fraction.minX * size.width, y: fraction.minY * size.height,
               width: fraction.width * size.width, height: fraction.height * size.height)
    }
}
