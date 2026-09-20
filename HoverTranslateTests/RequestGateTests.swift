import XCTest
@testable import HoverTranslate

final class RequestGateTests: XCTestCase {
    func testLateFirstResultCannotOverwriteSecond() {
        var gate = RequestGate()
        let first = gate.begin()
        let second = gate.begin()
        XCTAssertFalse(gate.accepts(first))
        XCTAssertTrue(gate.accepts(second))
    }
    func testReleaseInvalidatesOutstandingWork() {
        var gate = RequestGate()
        let current = gate.begin()
        gate.invalidate()
        XCTAssertFalse(gate.accepts(current))
    }
    func testNothingIsAcceptedBeforeFirstBegin() {
        var gate = RequestGate()
        XCTAssertFalse(gate.accepts(0))
        XCTAssertFalse(gate.accepts(1))
    }
    func testGenerationKeepsIncreasingAfterInvalidate() {
        var gate = RequestGate()
        let first = gate.begin()
        gate.invalidate()
        let second = gate.begin()
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(gate.accepts(second))
    }
}
