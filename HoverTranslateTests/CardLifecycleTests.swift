import AppKit
import XCTest
@testable import HoverTranslate

final class CardLifecycleTests: XCTestCase {
    @MainActor
    func testHoverPanelStaysAboveMenusWithoutTakingFocus() async throws {
        let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
        let presenter = FloatingPanelController()
        let panel = try XCTUnwrap(NSApp.windows.first { !existing.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer { presenter.dismiss() }
        XCTAssertGreaterThan(panel.level.rawValue, NSWindow.Level.popUpMenu.rawValue)
        XCTAssertLessThan(panel.level.rawValue, NSWindow.Level.screenSaver.rawValue)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.isKeyWindow)

        // Ask WindowServer about real windows, rather than only comparing the
        // constant. Reordering a menu must still leave the hover panel above it.
        let menu = NSPanel(contentRect: CGRect(x: 100, y: 100, width: 300, height: 180),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        menu.level = .popUpMenu
        menu.hidesOnDeactivate = false
        defer { menu.orderOut(nil) }
        menu.orderFrontRegardless()
        presenter.showStatus("Synthetic hover test", at: CGPoint(x: 160, y: 260))
        menu.orderFrontRegardless()
        var windows = WindowList.onScreen()
        for _ in 0..<2_000 {
            if windows.contains(where: { $0.windowID == CGWindowID(panel.windowNumber) }) &&
                windows.contains(where: { $0.windowID == CGWindowID(menu.windowNumber) }) { break }
            await Task.yield()
            windows = WindowList.onScreen()
        }
        let panelIndex = try XCTUnwrap(windows.firstIndex { $0.windowID == CGWindowID(panel.windowNumber) }, "hover window must reach WindowServer")
        let menuIndex = try XCTUnwrap(windows.firstIndex { $0.windowID == CGWindowID(menu.windowNumber) }, "synthetic menu must reach WindowServer")
        XCTAssertLessThan(panelIndex, menuIndex, "menu ordering must not cover the hover status")
        XCTAssertFalse(panel.isKeyWindow)
    }

    private let t0 = Date(timeIntervalSince1970: 2_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func testReleaseFreezesAndClosesAfterTheFreezeWindow() {
        var lifecycle = CardLifecycle()
        lifecycle.showLive(now: at(0))
        XCTAssertEqual(lifecycle.phase, .live)
        lifecycle.release(now: at(0))
        XCTAssertEqual(lifecycle.phase, .frozen)
        XCTAssertFalse(lifecycle.shouldClose(now: at(0.9)))
        XCTAssertTrue(lifecycle.shouldClose(now: at(1.0)))
    }

    func testPointerInsidePausesCloseAndOutsideUsesTheGracePeriod() {
        var lifecycle = CardLifecycle()
        lifecycle.showLive(now: at(0))
        lifecycle.release(now: at(0))
        lifecycle.pointerInside()
        XCTAssertFalse(lifecycle.shouldClose(now: at(30)))
        lifecycle.pointerOutside(now: at(30))
        XCTAssertFalse(lifecycle.shouldClose(now: at(30.5)))
        XCTAssertTrue(lifecycle.shouldClose(now: at(30.6)))
    }

    func testPinBlocksClosingAndNewContent() {
        var lifecycle = CardLifecycle()
        lifecycle.showLive(now: at(0))
        lifecycle.release(now: at(0))
        lifecycle.pin()
        XCTAssertEqual(lifecycle.phase, .pinned)
        XCTAssertFalse(lifecycle.acceptsNewContent)
        XCTAssertFalse(lifecycle.shouldClose(now: at(600)))
        lifecycle.pointerOutside(now: at(600))
        XCTAssertFalse(lifecycle.shouldClose(now: at(700)))
        lifecycle.showLive(now: at(700))
        XCTAssertEqual(lifecycle.phase, .pinned)
    }

    func testLiveCardAcceptsNewContentAndShowsNoButtons() {
        var lifecycle = CardLifecycle()
        lifecycle.showLive(now: at(0))
        XCTAssertTrue(lifecycle.acceptsNewContent)
        XCTAssertFalse(lifecycle.showsButtons)
        lifecycle.release(now: at(0))
        XCTAssertTrue(lifecycle.showsButtons)
    }

    func testDismissResetsEverything() {
        var lifecycle = CardLifecycle()
        lifecycle.showLive(now: at(0))
        lifecycle.pin()
        lifecycle.dismiss()
        XCTAssertEqual(lifecycle.phase, .hidden)
        XCTAssertFalse(lifecycle.isVisible)
        XCTAssertTrue(lifecycle.acceptsNewContent)
        XCTAssertFalse(lifecycle.shouldClose(now: at(1_000)))
    }
}
