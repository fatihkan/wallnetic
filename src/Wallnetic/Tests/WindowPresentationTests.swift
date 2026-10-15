import XCTest
import AppKit
import SwiftUI
@testable import Wallnetic

final class WindowPresentationTests: XCTestCase {
    @MainActor
    func testLibraryRoutingIgnoresWidePanelsAndUnregisteredWindows() {
        let router = WindowManager()
        let main = makeWindow(width: 600)
        let settings = makeWindow(width: 1000)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let overlay = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
                               styleMask: .borderless, backing: .buffered, defer: false)
        let windows = [settings, panel, overlay, main]
        for window in windows {
            window.isReleasedWhenClosed = false
            window.title = "Wallnetic" // Neither title nor width identifies the scene.
        }
        defer { windows.forEach { $0.close() } }
        router.registerMainWindow(main)
        router.registerMainWindow(panel)
        router.registerMainWindow(overlay)

        XCTAssertTrue(router.mainWindow(in: windows) === main)
        XCTAssertNil(router.mainWindow(in: [settings, panel, overlay]))
        XCTAssertNil(WindowManager().mainWindow(in: windows), "Membership belongs to this router")
    }

    @MainActor
    func testClosedMainWindowIsNotReusedEvenWhileAppKitRetainsIt() {
        let router = WindowManager()
        let main = makeWindow()
        let otherMain = makeWindow()
        defer { main.close(); otherMain.close() }
        router.registerMainWindow(main)
        router.registerMainWindow(otherMain)
        XCTAssertTrue(router.mainWindow(in: [main, otherMain]) === main)
        main.close()
        XCTAssertTrue(router.mainWindow(in: [main, otherMain]) === otherMain)
        otherMain.close()
        XCTAssertNil(router.mainWindow(in: [main, otherMain]))

        var opened = 0
        router.openMainWindow = { opened += 1 }
        router.showMainWindow()
        XCTAssertEqual(opened, 1, "A closed main scene must be reopened through SwiftUI")
        var explicitOpened = 0
        router.showMainWindow { explicitOpened += 1 }
        XCTAssertEqual(explicitOpened, 1)
        XCTAssertEqual(opened, 1, "The caller's scene action takes precedence")
    }

    @MainActor
    func testMinimizedLibraryIsRestoredWithoutOpeningAnotherScene() async throws {
        let router = WindowManager()
        let main = makeWindow()
        defer { main.close() }
        router.registerMainWindow(main)
        main.orderFront(nil)
        main.miniaturize(nil)
        let minimizedDeadline = Date().addingTimeInterval(3)
        while !main.isMiniaturized, Date() < minimizedDeadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(main.isMiniaturized)
        XCTAssertTrue(router.mainWindow(in: NSApp.windows) === main)
        var opened = 0
        router.showMainWindow { opened += 1 }
        let restoredDeadline = Date().addingTimeInterval(3)
        while main.isMiniaturized, Date() < restoredDeadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(main.isMiniaturized)
        XCTAssertTrue(main.isVisible)
        XCTAssertEqual(opened, 0)
    }

    @MainActor
    func testSceneChromeRegistersOnlyLibraryAndPreservesWindowIdentifiers() async throws {
        let main = makeWindow()
        let settings = makeWindow()
        main.identifier = NSUserInterfaceItemIdentifier("swiftui-main-fixture")
        settings.identifier = NSUserInterfaceItemIdentifier("swiftui-settings-fixture")
        defer { main.close(); settings.close() }
        main.contentView = NSHostingView(rootView: Color.clear.frame(width: 600, height: 400)
            .cinematicWindowChrome(isMainWindow: true))
        settings.contentView = NSHostingView(rootView: Color.clear.frame(width: 600, height: 400)
            .cinematicWindowChrome())
        let deadline = Date().addingTimeInterval(3)
        while WindowManager.shared.mainWindow(in: [main]) == nil, Date() < deadline {
            main.contentView?.layoutSubtreeIfNeeded()
            settings.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(WindowManager.shared.mainWindow(in: [settings, main]) === main)
        XCTAssertNil(WindowManager.shared.mainWindow(in: [settings]))
        XCTAssertEqual(main.identifier?.rawValue, "swiftui-main-fixture")
        XCTAssertEqual(settings.identifier?.rawValue, "swiftui-settings-fixture")
        main.close()
        XCTAssertNil(WindowManager.shared.mainWindow(in: [main]))
    }

    @MainActor
    private func makeWindow(width: CGFloat = 900) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

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
        let router = WindowManager()
        router.registerMainWindow(sheet)
        XCTAssertNil(router.mainWindow(in: [sheet]), "An onboarding sheet cannot become the Library window")
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
