import CoreGraphics
import Foundation

/// What the Dynamic Island needs to know about a display (#352).
struct IslandMetrics: Equatable {
    /// The hardware notch. Zero on a display without one.
    var notch: CGSize = .zero
    /// The height of the menu bar on this display. Zero when it is hidden.
    var menuBarHeight: CGFloat = 0

    var hasNotch: Bool { notch.width > 0 && notch.height > 0 }
}

/// The island's shape at one moment: a bar and a card that grows out of it.
/// `x` is measured from the island's centre line and `y` down from the
/// screen's top edge. The shape hangs from that edge on every display: its
/// top is flat and its upper corners flow into the edge as concave ears.
struct IslandLayout: Equatable {
    /// The part that is always there: the bar around the notch, or the bar
    /// that stands in for one on a display without a notch.
    var bar: CGRect
    /// The body that grows out of the bar. Equal to the bar while compact.
    var card: CGRect
    var barRadius: CGFloat
    var cardRadius: CGFloat
    var earRadius: CGFloat
    /// How visible the card is. Below 1 only while it fades (Reduce Motion).
    var cardOpacity: CGFloat
    /// How strong the glow is, from its resting share to 1 when open.
    var glow: CGFloat

    var bounds: CGRect { bar.union(card) }
}

enum IslandGeometry {
    /// Room beside the notch for the thumbnail and for the playback state.
    static let earWidth: CGFloat = 44
    /// The bar's width on a display without a notch.
    static let barWidth: CGFloat = 220
    /// The bar's height when the menu bar is hidden.
    static let fallbackBarHeight: CGFloat = 28
    static let cardWidth: CGFloat = 364
    /// The card's height below the bar.
    static let cardBodyHeight: CGFloat = 112
    /// Room around the shape for its glow. The glow ends inside it.
    static let margin: CGFloat = 18
    static let barCornerRadius: CGFloat = 10
    static let cardCornerRadius: CGFloat = 24
    static let earRadius: CGFloat = 8
    /// A compact island glows this much of what an open one does.
    static let restingGlow: CGFloat = 0.4
    /// A spring may pass its target a little. More than this is not drawn.
    static let maximumOvershoot: CGFloat = 0.08

    /// The compact shape, hanging from the screen's top edge: a bar of the
    /// notch's height that reaches past it on both sides, or, without a
    /// notch, a bar of the menu bar's height in the middle of the menu bar.
    static func compactBar(_ metrics: IslandMetrics) -> CGRect {
        if metrics.hasNotch {
            let width = metrics.notch.width + 2 * earWidth
            return CGRect(x: -width / 2, y: 0, width: width, height: metrics.notch.height)
        }
        let height = metrics.menuBarHeight > 0 ? metrics.menuBarHeight : fallbackBarHeight
        return CGRect(x: -barWidth / 2, y: 0, width: barWidth, height: height)
    }

    /// The expanded shape. It keeps the top edge and grows down and outwards.
    static func expandedCard(_ metrics: IslandMetrics) -> CGRect {
        let bar = compactBar(metrics)
        let width = max(cardWidth, bar.width + 2 * cardCornerRadius)
        return CGRect(x: -width / 2, y: 0, width: width, height: bar.height + cardBodyHeight)
    }

    /// The top of the expanded card that holds no content: the part a notch
    /// hides, or the strip at the menu bar's level.
    static func hiddenTop(_ metrics: IslandMetrics) -> CGFloat {
        compactBar(metrics).height
    }

    /// The shape for `progress`: 0 is compact and 1 is expanded. With
    /// `crossFades` the card does not stretch: it is drawn at full size and
    /// `progress` is its opacity.
    ///
    /// The card is one rounded rectangle that grows from the bar's own
    /// outline to the full card, with the top edge fixed. Bar and card are
    /// never blended: a blend swells wherever their edges lie on each other.
    static func layout(progress: CGFloat, metrics: IslandMetrics, crossFades: Bool = false) -> IslandLayout {
        let bar = compactBar(metrics)
        let full = expandedCard(metrics)
        let unit = min(max(progress, 0), 1)
        let glow = restingGlow + (1 - restingGlow) * unit
        if crossFades {
            return IslandLayout(bar: bar, card: full, barRadius: barCornerRadius, cardRadius: cardCornerRadius,
                                earRadius: earRadius, cardOpacity: unit, glow: glow)
        }
        let stretch = min(max(progress, 0), 1 + maximumOvershoot)
        let width = bar.width + (full.width - bar.width) * stretch
        let card = CGRect(x: -width / 2, y: 0, width: width,
                          height: bar.height + (full.height - bar.height) * stretch)
        return IslandLayout(bar: bar, card: card, barRadius: barCornerRadius,
                            cardRadius: barCornerRadius + (cardCornerRadius - barCornerRadius) * unit,
                            earRadius: earRadius, cardOpacity: 1, glow: glow)
    }

    /// The island's top centre on a display, in AppKit screen coordinates:
    /// the middle of the screen's top edge.
    static func anchor(screenFrame: CGRect) -> CGPoint {
        CGPoint(x: screenFrame.midX, y: screenFrame.maxY)
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
