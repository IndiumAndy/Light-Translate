import AppKit
import XCTest
@testable import HoverTranslate

/// v0.5: the list is exclusions, not permissions.
///
/// The user asked for the tool to work in every application without having to
/// add them one by one, so the empty list means "read everything" and adding an
/// application is what blocks it.
final class SourcePolicyTests: XCTestCase {
    func testAnEmptyExclusionListReadsEveryApplication() {
        let policy = SourcePolicy(excludedBundleIDs: [])
        XCTAssertTrue(policy.allows(bundleID: "com.apple.TextEdit"))
        XCTAssertTrue(policy.allows(bundleID: "com.apple.Safari"))
        XCTAssertTrue(policy.allows(bundleID: "com.example.anything"))
    }
    func testAnExcludedApplicationIsDenied() {
        let policy = SourcePolicy(excludedBundleIDs: ["com.apple.Safari"])
        XCTAssertFalse(policy.allows(bundleID: "com.apple.Safari"))
        XCTAssertTrue(policy.allows(bundleID: "com.apple.TextEdit"),
                      "excluding one application must not affect the others")
    }
    func testAnUnattributedSourceIsAlwaysDenied() {
        let policy = SourcePolicy(excludedBundleIDs: [])
        XCTAssertFalse(policy.allows(bundleID: nil))
        XCTAssertFalse(policy.allows(bundleID: ""))
    }
}

final class PointerWindowPickerTests: XCTestCase {
    func testOpenMenuIsTheSourceInsteadOfTheWindowBehindIt() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 300)
        let menu = PointerWindow(ownerPID: 11, layer: NSWindow.Level.popUpMenu.rawValue,
                                 bounds: rect, windowID: 77)
        let underneath = PointerWindow(ownerPID: 22, layer: 0, bounds: rect, windowID: 88)
        XCTAssertEqual(PointerWindowPicker.topmostWindow([menu, underneath],
                                                        at: CGPoint(x: 50, y: 50), excluding: 99), menu)
    }

    private func window(_ pid: pid_t, layer: Int = 0, _ rect: CGRect) -> PointerWindow {
        PointerWindow(ownerPID: pid, layer: layer, bounds: rect)
    }

    func testFrontmostWindowContainingThePointerWins() {
        let windows = [window(11, CGRect(x: 0, y: 0, width: 100, height: 100)),
                       window(22, CGRect(x: 0, y: 0, width: 100, height: 100))]
        XCTAssertEqual(PointerWindowPicker.topmostOwner(windows, at: CGPoint(x: 50, y: 50), excluding: 99), 11)
    }
    func testWindowWithoutThePointerIsSkipped() {
        let windows = [window(11, CGRect(x: 200, y: 200, width: 50, height: 50)),
                       window(22, CGRect(x: 0, y: 0, width: 100, height: 100))]
        XCTAssertEqual(PointerWindowPicker.topmostOwner(windows, at: CGPoint(x: 50, y: 50), excluding: 99), 22)
    }
    func testNonZeroLayerAndOwnProcessAreNeverTheSource() {
        let windows = [window(11, layer: 25, CGRect(x: 0, y: 0, width: 100, height: 100)),
                       window(99, CGRect(x: 0, y: 0, width: 100, height: 100))]
        XCTAssertNil(PointerWindowPicker.topmostOwner(windows, at: CGPoint(x: 50, y: 50), excluding: 99))
    }
}
