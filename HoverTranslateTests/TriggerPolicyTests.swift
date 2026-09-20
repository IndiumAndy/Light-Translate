import XCTest
@testable import HoverTranslate

final class TriggerPolicyTests: XCTestCase {
    func testLeftOptionDoesNotTriggerRightOptionMode() {
        XCTAssertNil(TriggerPolicy.mode(rightOption: false,
            leftOption: true, control: false, enabled: true,
            useRightOption: true))
    }
    func testReleaseRightOptionStopsEvenIfLeftStillHeld() {
        XCTAssertEqual(TriggerPolicy.mode(rightOption: true,
            leftOption: true, control: false, enabled: true,
            useRightOption: true), .word)
        XCTAssertNil(TriggerPolicy.mode(rightOption: false,
            leftOption: true, control: false, enabled: true,
            useRightOption: true))
    }
    func testDisabledNeverTriggers() {
        XCTAssertNil(TriggerPolicy.mode(rightOption: true,
            leftOption: false, control: false, enabled: false,
            useRightOption: true))
    }
    func testLeftOptionSettingUsesLeftKeyOnly() {
        XCTAssertEqual(TriggerPolicy.mode(rightOption: false,
            leftOption: true, control: false, enabled: true,
            useRightOption: false), .word)
        XCTAssertNil(TriggerPolicy.mode(rightOption: true,
            leftOption: false, control: false, enabled: true,
            useRightOption: false))
    }
    func testTriggerKeyIsNotObservableWithoutAccessibilityPermission() {
        XCTAssertFalse(TriggerController.isTriggerKeyObservable(trusted: false, hasMonitor: true))
        XCTAssertFalse(TriggerController.isTriggerKeyObservable(trusted: false, hasMonitor: false))
    }
    func testTriggerKeyIsObservableOnlyWithAMonitorAndPermission() {
        XCTAssertTrue(TriggerController.isTriggerKeyObservable(trusted: true, hasMonitor: true))
        XCTAssertFalse(TriggerController.isTriggerKeyObservable(trusted: true, hasMonitor: false))
    }
    /// 2026-09-18: the sentence modifier is Control, not Shift. Shift is the key
    /// people hold while adjusting a selection, so it is not a mode key here.
    func testControlUpgradesTheModeToSentence() {
        XCTAssertEqual(TriggerPolicy.mode(rightOption: true,
            leftOption: false, control: true, enabled: true,
            useRightOption: true), .sentence)
        XCTAssertEqual(TriggerPolicy.mode(rightOption: false,
            leftOption: true, control: true, enabled: true,
            useRightOption: false), .sentence)
    }
    func testReleasingControlReturnsToWordMode() {
        XCTAssertEqual(TriggerPolicy.mode(rightOption: true,
            leftOption: false, control: false, enabled: true,
            useRightOption: true), .word)
    }
    func testControlAloneIsNotATriggerAndDisabledStaysDisabled() {
        XCTAssertNil(TriggerPolicy.mode(rightOption: false,
            leftOption: false, control: true, enabled: true,
            useRightOption: true))
        XCTAssertNil(TriggerPolicy.mode(rightOption: true,
            leftOption: false, control: true, enabled: false,
            useRightOption: true))
    }
}
