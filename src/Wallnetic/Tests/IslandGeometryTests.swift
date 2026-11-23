import XCTest
import Metal
@testable import Wallnetic

/// The Dynamic Island's shape, spring and rules (#352).
final class IslandGeometryTests: XCTestCase {
    private let floating = IslandMetrics()
    private let notched = IslandMetrics(notch: CGSize(width: 200, height: 32))

    // MARK: - Shape

    func testADisplayWithoutANotchGetsAPillBelowTheMenuBar() {
        let bar = IslandGeometry.compactBar(floating)
        XCTAssertEqual(bar.size, IslandGeometry.pillSize)
        XCTAssertEqual(bar.midX, 0, "The island is centred")
        XCTAssertEqual(bar.minY, IslandGeometry.floatingGap, "It floats below its anchor")
        XCTAssertFalse(IslandGeometry.layout(progress: 0, metrics: floating).attached)
    }

    func testANotchGetsABarOfItsHeightWithAnEarOnEachSide() {
        let bar = IslandGeometry.compactBar(notched)
        XCTAssertEqual(bar.width, 200 + 2 * IslandGeometry.earWidth)
        XCTAssertEqual(bar.height, 32)
        XCTAssertEqual(bar.minY, 0, "It starts at the screen's top edge")
        XCTAssertEqual(bar.midX, 0)
        XCTAssertTrue(IslandGeometry.layout(progress: 0, metrics: notched).attached)
    }

    func testTheExpandedCardKeepsTheTopEdgeAndHoldsTheCompactShape() {
        for metrics in [floating, notched] {
            let bar = IslandGeometry.compactBar(metrics)
            let card = IslandGeometry.expandedCard(metrics)
            XCTAssertEqual(card.minY, bar.minY)
            XCTAssertTrue(card.contains(bar))
            XCTAssertEqual(card.midX, 0)
        }
        XCTAssertEqual(IslandGeometry.hiddenTop(notched), 32, "The notch hides the card's top")
        XCTAssertEqual(IslandGeometry.hiddenTop(floating), 0)
    }

    func testAtRestTheShapeIsExactlyTheBarOrTheCard() {
        for metrics in [floating, notched] {
            let compact = IslandGeometry.layout(progress: 0, metrics: metrics)
            let bar = IslandGeometry.compactBar(metrics)
            XCTAssertEqual(compact.bounds, bar, "A compact island is its bar and nothing more")
            // The card rests inside the bar, out of the blend's reach.
            XCTAssertGreaterThanOrEqual(compact.card.minX - bar.minX, IslandGeometry.blend - 0.001)
            XCTAssertGreaterThanOrEqual(bar.maxY - compact.card.maxY, IslandGeometry.blend - 0.001)

            let expanded = IslandGeometry.layout(progress: 1, metrics: metrics)
            XCTAssertEqual(expanded.card, IslandGeometry.expandedCard(metrics))
            XCTAssertEqual(expanded.blend, 0, accuracy: 0.0001, "No blend is left to swell the resting card")
            XCTAssertEqual(expanded.cardRadius, IslandGeometry.cardCornerRadius)
            XCTAssertEqual(expanded.cardOpacity, 1)
        }
    }

    func testTheCardGrowsSteadilyAndBlendsOnTheWay() {
        var last = IslandGeometry.layout(progress: 0, metrics: floating).card
        for step in 1...10 {
            let card = IslandGeometry.layout(progress: CGFloat(step) / 10, metrics: floating).card
            XCTAssertGreaterThan(card.width, last.width)
            XCTAssertGreaterThan(card.height, last.height)
            last = card
        }
        XCTAssertEqual(IslandGeometry.layout(progress: 0.5, metrics: floating).blend, IslandGeometry.blend)
    }

    func testOvershootIsBounded() {
        let limit = IslandGeometry.layout(progress: 1 + IslandGeometry.maximumOvershoot, metrics: floating)
        let beyond = IslandGeometry.layout(progress: 3, metrics: floating)
        XCTAssertEqual(beyond.card, limit.card)
        XCTAssertEqual(IslandGeometry.layout(progress: -2, metrics: floating),
                       IslandGeometry.layout(progress: 0, metrics: floating))
    }

    func testReduceMotionFadesTheCardInsteadOfStretchingIt() {
        let half = IslandGeometry.layout(progress: 0.5, metrics: notched, crossFades: true)
        XCTAssertEqual(half.card, IslandGeometry.expandedCard(notched), "The card is at full size from the start")
        XCTAssertEqual(half.cardOpacity, 0.5)
        XCTAssertEqual(half.blend, 0)
        XCTAssertEqual(IslandGeometry.layout(progress: 0, metrics: notched, crossFades: true).cardOpacity, 0)
        XCTAssertEqual(IslandGeometry.layout(progress: 1, metrics: notched, crossFades: true).cardOpacity, 1)
    }

    // MARK: - Window

    func testTheWindowHangsFromTheScreenTopOrFromTheMenuBar() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 950)
        XCTAssertEqual(IslandGeometry.anchor(screenFrame: screen, visibleFrame: visible, metrics: notched),
                       CGPoint(x: 756, y: 982))
        XCTAssertEqual(IslandGeometry.anchor(screenFrame: screen, visibleFrame: visible, metrics: floating),
                       CGPoint(x: 756, y: 950))
    }

    func testTheWindowHoldsTheShapeAndItsGlowAndKeepsItsTopCentre() {
        let anchor = CGPoint(x: 960, y: 1050)
        for metrics in [floating, notched] {
            let compact = IslandGeometry.windowFrame(expanded: false, metrics: metrics, anchor: anchor)
            let expanded = IslandGeometry.windowFrame(expanded: true, metrics: metrics, anchor: anchor)
            for frame in [compact, expanded] {
                XCTAssertEqual(frame.midX, anchor.x)
                XCTAssertEqual(frame.maxY, anchor.y)
            }
            let bar = IslandGeometry.compactBar(metrics)
            XCTAssertEqual(compact.width, bar.width + 2 * IslandGeometry.margin)
            XCTAssertEqual(compact.height, bar.maxY + IslandGeometry.margin)
            XCTAssertGreaterThan(expanded.width, compact.width)
            XCTAssertGreaterThan(expanded.height, compact.height)
        }
    }

    // MARK: - Spring

    func testTheSpringReachesItsTargetAndRests() {
        var spring = IslandSpring()
        spring.target = 1
        var peak: CGFloat = 0
        var frames = 0
        while !spring.isSettled, frames < 600 {
            spring.advance(by: 1.0 / 60)
            peak = max(peak, spring.value)
            frames += 1
        }
        XCTAssertTrue(spring.isSettled)
        XCTAssertEqual(spring.value, 1)
        XCTAssertEqual(spring.velocity, 0)
        XCTAssertLessThan(frames, 120, "It rests within two seconds")
        XCTAssertGreaterThan(peak, 1, "It passes the target a little: that is the liquid feel")
        XCTAssertLessThanOrEqual(peak, 1 + IslandGeometry.maximumOvershoot)
    }

    func testALateFrameDoesNotThrowTheSpring() {
        var spring = IslandSpring()
        spring.target = 1
        spring.advance(by: 5)
        XCTAssertTrue(spring.value.isFinite)
        XCTAssertLessThan(abs(spring.value), 2)
    }

    func testTheFadeMovesAtAConstantRateAndStopsAtTheTarget() {
        var spring = IslandSpring()
        spring.target = 1
        spring.fade(by: IslandSpring.fadeDuration / 2)
        XCTAssertEqual(spring.value, 0.5, accuracy: 0.0001)
        spring.fade(by: 1)
        XCTAssertEqual(spring.value, 1)
        spring.target = 0
        spring.fade(by: IslandSpring.fadeDuration / 4)
        XCTAssertEqual(spring.value, 0.75, accuracy: 0.0001)
    }

    // MARK: - Rules

    func testTheIslandDoesNotOpenByItselfWhileTheUserTypes() {
        XCTAssertFalse(IslandPolicy.mayOpenUnasked(secondsSinceLastKey: 0.2))
        XCTAssertFalse(IslandPolicy.mayOpenUnasked(secondsSinceLastKey: IslandPolicy.typingQuietTime - 0.01))
        XCTAssertTrue(IslandPolicy.mayOpenUnasked(secondsSinceLastKey: IslandPolicy.typingQuietTime))
        XCTAssertTrue(IslandPolicy.mayOpenUnasked(secondsSinceLastKey: 600))
    }

    func testTheIslandStepsAsideForAFullScreenApp() {
        XCTAssertTrue(IslandPolicy.isShown(enabled: true, fullscreenAppActive: false))
        XCTAssertFalse(IslandPolicy.isShown(enabled: true, fullscreenAppActive: true))
        XCTAssertFalse(IslandPolicy.isShown(enabled: false, fullscreenAppActive: false))
    }

    // MARK: - Surface

    /// The shader is compiled from source when the app runs, so a mistake in
    /// it shows only here or on screen.
    func testTheSurfaceShaderCompiles() throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "No Metal device")
        XCTAssertTrue(IslandSurfaceView().isAvailable)
    }

    func testTheSurfaceDrawsOnlyWhenSomethingChanges() throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "No Metal device")
        let (surface, window) = makeSurface(width: 300, height: 120)
        defer { window.close() }

        let compact = IslandGeometry.layout(progress: 0, metrics: floating)
        surface.show(compact, style: IslandStyle())
        surface.renderIfDirty()
        let afterFirst = surface.drawCount
        try XCTSkipIf(afterFirst == 0, "No drawable in this environment")

        surface.show(compact, style: IslandStyle())
        surface.renderIfDirty()
        surface.renderIfDirty()
        XCTAssertEqual(surface.drawCount, afterFirst, "The same shape again draws nothing")

        surface.show(IslandGeometry.layout(progress: 0.5, metrics: floating), style: IslandStyle())
        surface.renderIfDirty()
        XCTAssertEqual(surface.drawCount, afterFirst + 1)

        var contrast = IslandStyle()
        contrast.increasesContrast = true
        surface.show(IslandGeometry.layout(progress: 0.5, metrics: floating), style: contrast)
        surface.renderIfDirty()
        XCTAssertEqual(surface.drawCount, afterFirst + 2, "A new style draws once")
    }

    /// The island's window changes size when it opens and closes. A frame
    /// drawn for the old size and left on screen put the shape beside its
    /// content, so a new size must always bring one frame of that size.
    func testANewSizeBringsOneFrameOfThatSize() throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "No Metal device")
        let (surface, window) = makeSurface(width: 400, height: 148)
        defer { window.close() }
        let scale = window.backingScaleFactor

        surface.show(IslandGeometry.layout(progress: 1, metrics: floating), style: IslandStyle())
        surface.renderIfDirty()
        let afterFirst = surface.drawCount
        try XCTSkipIf(afterFirst == 0, "No drawable in this environment")
        XCTAssertEqual(surface.drawableSize, CGSize(width: 400 * scale, height: 148 * scale))

        // As at the end of a collapse: a new shape, then a smaller window.
        surface.show(IslandGeometry.layout(progress: 0, metrics: floating), style: IslandStyle())
        surface.setFrameSize(CGSize(width: 256, height: 54))
        surface.renderIfDirty()
        XCTAssertEqual(surface.drawCount, afterFirst + 1, "Shape and size together are one frame, not two")
        XCTAssertEqual(surface.drawableSize, CGSize(width: 256 * scale, height: 54 * scale))

        // A size change alone is also a frame.
        surface.setFrameSize(CGSize(width: 400, height: 148))
        surface.renderIfDirty()
        XCTAssertEqual(surface.drawCount, afterFirst + 2)
        XCTAssertEqual(surface.drawableSize, CGSize(width: 400 * scale, height: 148 * scale))

        // The same size again is not.
        surface.setFrameSize(CGSize(width: 400, height: 148))
        surface.renderIfDirty()
        XCTAssertEqual(surface.drawCount, afterFirst + 2)
    }

    func testAnOldFrameIsNeverStretchedToTheView() {
        let surface = IslandSurfaceView()
        XCTAssertEqual(surface.layer?.contentsGravity, .top,
                       "A frame of another size hangs from the top centre at its own scale")
    }

    private func makeSurface(width: CGFloat, height: CGFloat) -> (IslandSurfaceView, NSWindow) {
        let surface = IslandSurfaceView()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        // A plain container, so the test sets the surface's size itself.
        let container = NSView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.contentView = container
        surface.frame = container.bounds
        container.addSubview(surface)
        return (surface, window)
    }
}
