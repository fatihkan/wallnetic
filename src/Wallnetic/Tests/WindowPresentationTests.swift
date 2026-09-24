import XCTest
import AppKit
import SwiftUI
@testable import Wallnetic

final class WindowPresentationTests: XCTestCase {
    @MainActor
    func testNativeControlsStayOutsideContentAfterChromeUpdates() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        window.titlebarAppearsTransparent = true
        WindowChrome.configureAppWindow(window)
        WindowChrome.configureAppWindow(window)
        window.contentView?.superview?.layoutSubtreeIfNeeded()

        XCTAssertFalse(window.styleMask.contains(.fullSizeContentView))
        XCTAssertFalse(window.titlebarAppearsTransparent)
        let content = try XCTUnwrap(window.contentView)
        let contentInWindow = content.convert(content.bounds, to: nil)
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            let button = try XCTUnwrap(window.standardWindowButton(type))
            XCTAssertFalse(button.isHidden)
            XCTAssertGreaterThan(button.alphaValue, 0)
            XCTAssertNotNil(button.target)
            XCTAssertNotNil(button.action)
            let buttonInWindow = button.convert(button.bounds, to: nil)
            XCTAssertFalse(contentInWindow.intersects(buttonInWindow), "Native controls must not share the SwiftUI content area")
        }
    }

    @MainActor
    func testChromeLeavesPanelsAndBorderlessWindowsAlone() {
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        let overlay = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        for window in [panel, overlay] {
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
            let mask = window.styleMask
            WindowChrome.configureAppWindow(window)
            XCTAssertEqual(window.styleMask, mask)
            XCTAssertTrue(window.titlebarAppearsTransparent)
            XCTAssertFalse(window.isOpaque)
        }
    }

    @MainActor
    func testOnboardingSheetUsesItsContentSize() async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingPresentationHost())
        defer {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        window.orderFront(nil)
        let deadline = Date().addingTimeInterval(3)
        while window.attachedSheet == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let sheet = try XCTUnwrap(window.attachedSheet)
        sheet.contentView?.layoutSubtreeIfNeeded()
        let content = try XCTUnwrap(sheet.contentView)
        XCTAssertEqual(content.bounds.width, 640, accuracy: 1)
        XCTAssertEqual(content.bounds.height, 520, accuracy: 1)

        let originalMask = sheet.styleMask
        WindowChrome.configureAppWindow(sheet)
        XCTAssertEqual(sheet.styleMask, originalMask)
    }
}

private struct OnboardingPresentationHost: View {
    @State private var isPresented = false
    var body: some View {
        Color.clear.frame(width: 900, height: 600)
            .sheet(isPresented: $isPresented) {
                OnboardingView(isPresented: $isPresented)
            }
            .onAppear { isPresented = true }
    }
}
