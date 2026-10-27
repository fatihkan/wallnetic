import AppKit

/// The clock drawn in a display's wallpaper window (#311): above the video and
/// the effects, below desktop icons and windows, click-through. Its content is
/// a static image, drawn again only when its text, size, place, scale or the
/// contrast setting changes. It is never animated and is not an accessibility
/// element; the menu-bar clock stays the accessible source.
final class DesktopClockView: NSView {
    struct Content: Equatable {
        var time: String
        var date: String?
        var fontSize: CGFloat
        var position: DesktopClockSettings.Position
        /// The display's visible area in window coordinates.
        var visibleRect: CGRect
        var scale: CGFloat
        /// Increase Contrast or Reduce Transparency: a solid backdrop.
        var backdrop: Bool
    }

    private let imageLayer = CALayer()
    private(set) var content: Content?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        // No implicit animation for anything a minute change or a hide touches.
        imageLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull(),
                              "hidden": NSNull(), "opacity": NSNull(), "contentsScale": NSNull()]
        layer?.addSublayer(imageLayer)
        setAccessibilityElement(false)
        isHidden = true
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func accessibilityChildren() -> [Any]? { [] }

    /// Shows `content`, drawing it first when it changed, so a clock that
    /// appears already shows the current time.
    func show(_ next: Content) {
        if next != content {
            content = next
            draw(next)
        }
        if isHidden { isHidden = false }
    }

    func hide() {
        if !isHidden { isHidden = true }
    }

    private func draw(_ content: Content) {
        let image = Self.image(for: content)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contentsScale = content.scale
        imageLayer.contents = image.layerContents(forContentsScale: content.scale)
        let origin = DesktopClockLayout.origin(for: image.size, in: content.visibleRect, position: content.position)
        imageLayer.frame = CGRect(origin: origin, size: image.size)
        CATransaction.commit()
    }

    /// White text with a soft shadow drawn into the image itself, not a live
    /// layer shadow or blur, so nothing behind it is recomputed per frame.
    static func image(for content: Content) -> NSImage {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
        shadow.shadowBlurRadius = max(2, (content.fontSize * 0.06).rounded())
        shadow.shadowOffset = NSSize(width: 0, height: -max(1, (content.fontSize * 0.015).rounded()))
        let paragraph = NSMutableParagraphStyle()
        switch content.position {
        case .topLeading, .bottomLeading: paragraph.alignment = .left
        case .topCenter, .center, .bottomCenter: paragraph.alignment = .center
        case .bottomTrailing: paragraph.alignment = .right
        }
        func attributes(font: NSFont) -> [NSAttributedString.Key: Any] {
            [.font: font, .foregroundColor: NSColor.white, .shadow: shadow, .paragraphStyle: paragraph]
        }
        let time = NSAttributedString(string: content.time, attributes: attributes(font: timeFont(content.fontSize)))
        let date = content.date.map {
            NSAttributedString(string: $0, attributes: attributes(font: dateFont(content.fontSize)))
        }
        let timeSize = time.size()
        let dateSize = date?.size() ?? .zero
        let padding = ceil(shadow.shadowBlurRadius * 2 + content.fontSize * (content.backdrop ? 0.15 : 0))
        let spacing = date == nil ? 0 : ceil(content.fontSize * 0.06)
        let size = NSSize(width: ceil(max(timeSize.width, dateSize.width)) + padding * 2,
                          height: ceil(timeSize.height + spacing + dateSize.height) + padding * 2)
        return NSImage(size: size, flipped: false) { rect in
            if content.backdrop {
                NSColor.black.withAlphaComponent(0.7).setFill()
                let radius = content.fontSize * 0.2
                NSBezierPath(roundedRect: rect.insetBy(dx: shadow.shadowBlurRadius, dy: shadow.shadowBlurRadius),
                             xRadius: radius, yRadius: radius).fill()
            }
            let inner = rect.insetBy(dx: padding, dy: padding)
            time.draw(in: NSRect(x: inner.minX, y: inner.maxY - ceil(timeSize.height), width: inner.width,
                                 height: ceil(timeSize.height)))
            date?.draw(in: NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: ceil(dateSize.height)))
            return true
        }
    }

    /// The widest of `times` and of `dates` in the clock's fonts.
    static func widest(times: [String], dates: [String], fontSize: CGFloat) -> (time: String, date: String?) {
        func widest(_ texts: [String], font: NSFont) -> String? {
            texts.map { ($0, NSAttributedString(string: $0, attributes: [.font: font]).size().width) }
                .max { $0.1 < $1.1 }?.0
        }
        return (widest(times, font: timeFont(fontSize)) ?? "", widest(dates, font: dateFont(fontSize)))
    }

    private static func timeFont(_ fontSize: CGFloat) -> NSFont {
        .monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
    }

    private static func dateFont(_ fontSize: CGFloat) -> NSFont {
        .systemFont(ofSize: (fontSize * 0.3).rounded(), weight: .medium)
    }
}
