import XCTest
@testable import Wallnetic

/// `AIGenerateViewModel` — UI-pure helpers (#166).
/// Network round-trip is not exercised — the singleton AIService isn't
/// dependency-injected in production. We assert state shape and lifecycle.
@MainActor
final class AIGenerateViewModelTests: XCTestCase {
    func testInitialStateIsIdle() {
        let vm = AIGenerateViewModel()
        XCTAssertFalse(vm.isGenerating)
        XCTAssertEqual(vm.generationProgress, 0)
        XCTAssertEqual(vm.generationStatus, "")
        XCTAssertNil(vm.generatedVideoURL)
        XCTAssertEqual(vm.estimatedTimeRemaining, "")
        XCTAssertNil(vm.errorMessage)
    }

    func testCancelClearsGenerationState() {
        let vm = AIGenerateViewModel()

        // Manually transition to "generating" without actually firing AIService.
        vm.isGenerating = true
        vm.generationProgress = 0.5
        vm.generationStatus = "Almost there"
        vm.estimatedTimeRemaining = "~30s remaining"

        vm.cancelGeneration()

        XCTAssertFalse(vm.isGenerating)
        XCTAssertEqual(vm.generationProgress, 0)
        XCTAssertEqual(vm.generationStatus, "")
        XCTAssertEqual(vm.estimatedTimeRemaining, "")
    }

    func testClearGeneratedVideo() {
        let vm = AIGenerateViewModel()
        vm.generatedVideoURL = URL(fileURLWithPath: "/tmp/test.mp4")
        vm.clearGeneratedVideo()
        XCTAssertNil(vm.generatedVideoURL)
    }
}
