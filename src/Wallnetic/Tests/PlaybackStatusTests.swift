import XCTest
import AVFoundation
@testable import Wallnetic

final class PlaybackStatusTests: XCTestCase {
    private func status(_ renderer: RendererPlaybackState, reasons: [PlaybackPauseReason] = [],
                        id: UInt32 = 1, hasWallpaper: Bool = true) -> DisplayPlaybackStatus {
        DisplayPlaybackStatus(id: id, displayName: "Display \(id)", hasWallpaper: hasWallpaper,
                              renderer: renderer, reasons: reasons)
    }

    func testObservedStateDistinguishesLoadingWaitingPausedAndPlaying() {
        XCTAssertEqual(status(.loading).state, .loading)
        XCTAssertEqual(status(.waiting).state, .waiting)
        XCTAssertEqual(status(.paused).state, .paused)
        XCTAssertEqual(status(.playing).state, .playing)
        XCTAssertEqual(status(.idle, hasWallpaper: false).state, .notSet)
        XCTAssertFalse(status(.loading).canRetry)
    }

    func testEveryRestrictionHasStablePriorityAndCannotBeBypassed() {
        for first in PlaybackPauseReason.allCases {
            for second in PlaybackPauseReason.allCases {
                let a = status(.playing, reasons: [first, second, first])
                let b = status(.paused, reasons: [second, first])
                XCTAssertEqual(a, b)
                XCTAssertEqual(a.state, .paused)
                XCTAssertEqual(a.title, min(first.rawValue, second.rawValue) == first.rawValue ? first.title : second.title)
                XCTAssertEqual(a.blocksResume, first.blocksResume || second.blocksResume)
                if first != second { XCTAssertFalse(a.detail.isEmpty) }
            }
        }
    }

    func testUnavailableKeepsRecoveryAndAllPauseReasons() {
        for failure in [RendererPlaybackFailure.missingFile, .unplayable, .loadFailed] {
            let value = status(.failed(failure), reasons: [.battery, .manual])
            XCTAssertEqual(value.state, .unavailable(failure))
            XCTAssertTrue(value.canRetry)
            XCTAssertTrue(value.blocksResume)
            XCTAssertTrue(value.detail.contains(failure.recovery))
            XCTAssertTrue(value.detail.contains(PlaybackPauseReason.manual.title))
            XCTAssertTrue(value.detail.contains(PlaybackPauseReason.battery.title))
        }
    }

    func testDisplaysKeepDifferentStatesAndAccessibleText() {
        let first = status(.paused, reasons: [.timer], id: 1)
        let second = status(.playing, id: 2)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.title, "Playback timer finished")
        XCTAssertEqual(second.title, "Playing")
        XCTAssertFalse(first.blocksResume)
        XCTAssertFalse(first.symbol.isEmpty)
        XCTAssertFalse(first.detail.isEmpty)
    }

    @MainActor
    func testQueuedPlayerCallbacksCannotOverwriteFailureOrCleanup() async {
        let monitor = RendererPlaybackMonitor()
        let player = AVPlayer()
        monitor.beginLoad()
        monitor.attach(player)
        monitor.framePresented()
        monitor.fail(.missingFile)
        await drainMainQueue()
        XCTAssertEqual(monitor.state, .failed(.missingFile))
        monitor.beginLoad()
        monitor.attach(player)
        monitor.reset()
        await drainMainQueue()
        XCTAssertEqual(monitor.state, .idle)
    }

    @MainActor
    func testStatusDeduplicatesEventsAndNeverStartsPlayer() async {
        let monitor = RendererPlaybackMonitor()
        let player = AVPlayer()
        var changes = 0
        monitor.onChange = { changes += 1 }
        monitor.beginLoad()
        monitor.beginLoad()
        XCTAssertEqual(changes, 1)
        monitor.attach(player)
        await drainMainQueue()
        XCTAssertEqual(monitor.state, .loading, "An attached player without a frame is not playing")
        monitor.framePresented()
        monitor.framePresented()
        XCTAssertEqual(monitor.state, .paused)
        XCTAssertEqual(changes, 2)
        XCTAssertEqual(player.rate, 0, "Status observation never issues Play")
    }

    @MainActor
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
