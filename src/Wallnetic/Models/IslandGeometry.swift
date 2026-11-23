import CoreGraphics
import Foundation

/// What the Dynamic Island needs to know about a display (#352).
struct IslandMetrics: Equatable {
    /// The hardware notch. Zero on a display without one.
    var notch: CGSize = .zero

    var hasNotch: Bool { notch.width > 0 && notch.height > 0 }
}

/// The island's liquid shape at one moment: a bar and a card that melt into
/// each other. `x` is measured from the island's centre line and `y` down
/// from its top anchor: the screen's top edge on a display with a notch, the
/// lower edge of the menu bar on any other.
struct IslandLayout: Equatable {
    /// The part that is always there: the bar around the notch, or the pill.
    var bar: CGRect
    /// The body that grows out of the bar. Equal to the bar while compact.
    var card: CGRect
    var barRadius: CGFloat
    var cardRadius: CGFloat
    /// The distance over which bar and card blend.
    var blend: CGFloat
    /// The shape joins the screen's top edge: a flat top with concave ears.
    var attached: Bool
    var earRadius: CGFloat
    /// How visible the card is. Below 1 only while it fades (Reduce Motion).
    var cardOpacity: CGFloat

    var bounds: CGRect { bar.union(card) }
}

enum IslandGeometry {
    /// Room beside the notch for the thumbnail and for the playback state.
    static let earWidth: CGFloat = 44
    static let pillSize = CGSize(width: 220, height: 30)
    static let cardWidth: CGFloat = 364
    /// The card's height below the notch.
    static let cardBodyHeight: CGFloat = 112
    static let floatingCardHeight: CGFloat = 124
    /// Space between the menu bar and a floating island.
    static let floatingGap: CGFloat = 6
    /// Room around the shape for its glow.
    static let margin: CGFloat = 18
    static let notchCornerRadius: CGFloat = 10
    static let cardCornerRadius: CGFloat = 24
    static let earRadius: CGFloat = 8
    static let blend: CGFloat = 14
    /// A spring may pass its target a little. More than this is not drawn.
    static let maximumOvershoot: CGFloat = 0.08

    /// The compact shape: a bar the height of the notch that reaches past it
    /// on both sides, or a pill below the menu bar.
    static func compactBar(_ metrics: IslandMetrics) -> CGRect {
        if metrics.hasNotch {
            let width = metrics.notch.width + 2 * earWidth
            return CGRect(x: -width / 2, y: 0, width: width, height: metrics.notch.height)
        }
        return CGRect(x: -pillSize.width / 2, y: floatingGap, width: pillSize.width, height: pillSize.height)
    }

    /// The expanded shape. It keeps the compact shape's top edge.
    static func expandedCard(_ metrics: IslandMetrics) -> CGRect {
        if metrics.hasNotch {
            let width = max(cardWidth, compactBar(metrics).width + 2 * blend)
            return CGRect(x: -width / 2, y: 0, width: width, height: metrics.notch.height + cardBodyHeight)
        }
        return CGRect(x: -cardWidth / 2, y: floatingGap, width: cardWidth, height: floatingCardHeight)
    }

    /// The top of the expanded card that the notch hides.
    static func hiddenTop(_ metrics: IslandMetrics) -> CGFloat {
        metrics.hasNotch ? metrics.notch.height : 0
    }

    /// The shape for `progress`: 0 is compact and 1 is expanded. With
    /// `crossFades` the card does not stretch: it is drawn at full size and
    /// `progress` is its opacity.
    static func layout(progress: CGFloat, metrics: IslandMetrics, crossFades: Bool = false) -> IslandLayout {
        let bar = compactBar(metrics)
        let full = expandedCard(metrics)
        let barRadius = metrics.hasNotch ? notchCornerRadius : bar.height / 2
        let unit = min(max(progress, 0), 1)
        if crossFades {
            return IslandLayout(bar: bar, card: full, barRadius: barRadius, cardRadius: cardCornerRadius,
                                blend: 0, attached: metrics.hasNotch, earRadius: earRadius, cardOpacity: unit)
        }
        let stretch = min(max(progress, 0), 1 + maximumOvershoot)
        // The card starts inside the bar, a blend's width from its edges, and
        // pushes out through it. Two shapes whose edges lie on each other
        // would swell there, so at rest only one of them shows: the bar while
        // compact, and the card, with the blend faded out, while expanded.
        let seed = seedCard(in: bar, attached: metrics.hasNotch)
        let card = CGRect(x: seed.minX + (full.minX - seed.minX) * stretch,
                          y: seed.minY + (full.minY - seed.minY) * stretch,
                          width: seed.width + (full.width - seed.width) * stretch,
                          height: seed.height + (full.height - seed.height) * stretch)
        let settling = min(max((unit - 0.7) / 0.3, 0), 1)
        return IslandLayout(bar: bar, card: card, barRadius: barRadius,
                            cardRadius: barRadius + (cardCornerRadius - barRadius) * unit,
                            blend: blend * (1 - settling * settling * (3 - 2 * settling)),
                            attached: metrics.hasNotch, earRadius: earRadius, cardOpacity: 1)
    }

    /// Where the card rests while the island is compact: inside the bar, far
    /// enough from its edges that the blend does not reach them. An attached
    /// shape has no top edge in view, so its card keeps the bar's top.
    static func seedCard(in bar: CGRect, attached: Bool) -> CGRect {
        let inset = min(blend, bar.width / 2 - 1, bar.height / 2 - 1)
        if attached {
            return CGRect(x: bar.minX + inset, y: bar.minY, width: bar.width - 2 * inset, height: bar.height - inset)
        }
        return bar.insetBy(dx: inset, dy: inset)
    }

    /// The island's top centre on a display, in AppKit screen coordinates.
    static func anchor(screenFrame: CGRect, visibleFrame: CGRect, metrics: IslandMetrics) -> CGPoint {
        CGPoint(x: screenFrame.midX, y: metrics.hasNotch ? screenFrame.maxY : visibleFrame.maxY)
    }

    /// The window that holds the compact or the expanded shape and its glow.
    /// It hangs from the anchor, so its top centre never moves.
    static func windowFrame(expanded: Bool, metrics: IslandMetrics, anchor: CGPoint) -> CGRect {
        let shape = expanded ? expandedCard(metrics) : compactBar(metrics)
        let width = shape.width + 2 * margin
        let height = shape.maxY + margin
        return CGRect(x: anchor.x - width / 2, y: anchor.y - height, width: width, height: height)
    }
}

/// The spring that stretches the island between compact and expanded.
struct IslandSpring: Equatable {
    var value: CGFloat = 0
    var velocity: CGFloat = 0
    var target: CGFloat = 0

    /// Seconds for one swing, and how quickly the swing dies out (1 would
    /// not pass the target at all).
    static let response: CGFloat = 0.38
    static let dampingFraction: CGFloat = 0.74
    /// The duration of the fade that replaces the spring under Reduce Motion.
    static let fadeDuration: CGFloat = 0.18

    var isSettled: Bool { abs(target - value) < 0.0005 && abs(velocity) < 0.005 }

    /// Moves the spring on by `seconds`, in steps small enough to stay stable
    /// when a frame is late.
    mutating func advance(by seconds: CGFloat) {
        let stiffness = pow(2 * .pi / Self.response, 2)
        let damping = 4 * .pi * Self.dampingFraction / Self.response
        var remaining = min(max(seconds, 0), 0.1)
        while remaining > 0 {
            let step = min(remaining, 1.0 / 240)
            velocity += (stiffness * (target - value) - damping * velocity) * step
            value += velocity * step
            remaining -= step
        }
        if isSettled { settle() }
    }

    /// Moves straight towards the target at a constant rate: a fade.
    mutating func fade(by seconds: CGFloat) {
        let step = max(seconds, 0) / Self.fadeDuration
        value = target > value ? min(target, value + step) : max(target, value - step)
        velocity = 0
    }

    mutating func settle() {
        value = target
        velocity = 0
    }
}

/// When the island shows and when it may open by itself.
enum IslandPolicy {
    /// After a key press, the island does not open by itself for this long.
    static let typingQuietTime: TimeInterval = 3

    /// Hovering always opens the island. Opening unasked, after a wallpaper
    /// change, waits until the user has stopped typing.
    static func mayOpenUnasked(secondsSinceLastKey: TimeInterval) -> Bool {
        secondsSinceLastKey >= typingQuietTime
    }

    /// The island steps aside while an app is in full screen.
    static func isShown(enabled: Bool, fullscreenAppActive: Bool) -> Bool {
        enabled && !fullscreenAppActive
    }
}
