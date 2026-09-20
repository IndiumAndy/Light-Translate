import XCTest
@testable import HoverTranslate

/// v0.5: the preference the policy reads, and the one upgrade trap it must not
/// fall into.
@MainActor
final class SettingsStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "HoverTranslateTests-" + UUID().uuidString
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func store() -> SettingsStore { SettingsStore(defaults: defaults) }

    func testEverythingIsReadableByDefault() {
        XCTAssertTrue(store().excludedBundleIDs.isEmpty)
        XCTAssertTrue(SourcePolicy(excludedBundleIDs: store().excludedBundleIDs).allows(bundleID: "com.apple.Safari"))
    }

    /// The v0.1-v0.4 allow list said "only these applications may be read".
    /// Reading it as an exclusion list would block exactly the applications the
    /// user had chosen, so the two settings must stay separate keys.
    func testTheOldAllowListIsNeverReadAsAnExclusionList() {
        defaults.set(["com.apple.TextEdit", "com.openai.codex"], forKey: "HoverTranslate.allowedBundleIDs")
        XCTAssertTrue(store().excludedBundleIDs.isEmpty,
                      "the legacy allow list must not turn into exclusions")
    }

    func testExclusionsPersistAndCanBeUndone() {
        let first = store()
        first.exclude(bundleID: "com.apple.Safari")
        first.exclude(bundleID: "   ")
        XCTAssertEqual(first.excludedBundleIDs, ["com.apple.Safari"])

        let reopened = store()
        XCTAssertEqual(reopened.excludedBundleIDs, ["com.apple.Safari"])
        XCTAssertFalse(SourcePolicy(excludedBundleIDs: reopened.excludedBundleIDs).allows(bundleID: "com.apple.Safari"))
        XCTAssertTrue(SourcePolicy(excludedBundleIDs: reopened.excludedBundleIDs).allows(bundleID: "com.apple.TextEdit"))

        reopened.stopExcluding(bundleID: "com.apple.Safari")
        XCTAssertTrue(store().excludedBundleIDs.isEmpty)
    }

    /// The screenshot fallback is opt-in: nothing captures anything by default.
    func testTheScreenshotFallbackIsOffByDefault() {
        XCTAssertFalse(store().isOCRFallbackEnabled)
    }

    func testTheTriggerKeyAndShortcutDefaultsAreUnchanged() {
        let store = store()
        XCTAssertTrue(store.useRightOption)
        XCTAssertFalse(store.isEnabled, "extraction is off until the user turns it on")
        XCTAssertEqual(SelectionShortcut.choice(at: store.selectionShortcutIndex), .default)
    }
}
