import XCTest
@testable import HoverTranslate

final class HoverDwellTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func testDoesNotStartBeforeDwellElapsed() {
        var dwell = HoverDwell()
        XCTAssertEqual(dwell.pointerMoved(to: CGPoint(x: 10, y: 10), at: at(0)), .none)
        XCTAssertEqual(dwell.pointerMoved(to: CGPoint(x: 10, y: 10), at: at(0.2)), .none)
    }

    func testStartsAfterDwellElapsedWithStillPointer() {
        var dwell = HoverDwell()
        XCTAssertEqual(dwell.pointerMoved(to: CGPoint(x: 10, y: 10), at: at(0)), .none)
        XCTAssertEqual(dwell.pointerMoved(to: CGPoint(x: 10, y: 10), at: at(0.25)), .start)
    }

    func testStartIsNotRepeatedWhilePointerStaysPut() {
        var dwell = HoverDwell()
        _ = dwell.pointerMoved(to: CGPoint(x: 10, y: 10), at: at(0))
        XCTAssertEqual(dwell.pointerMoved(to: CGPoint(x: 10, y: 10), at: at(0.25)), .start)
        XCTAssertEqual(dwell.pointerMoved(to: CGPoint(x: 10, y: 10), at: at(1.0)), .none)
    }

    func testJitterInsideRadiusStillStarts() {
        var dwell = HoverDwell()
        _ = dwell.pointerMoved(to: CGPoint(x: 10, y: 10), at: at(0))
        XCTAssertEqual(dwell.pointerMoved(to: CGPoint(x: 12, y: 10), at: at(0.1)), .none)
        XCTAssertEqual(dwell.pointerMoved(to: CGPoint(x: 8, y: 9), at: at(0.2)), .none)
        XCTAssertEqual(dwell.pointerMoved(to: CGPoint(x: 9, y: 10), at: at(0.25)), .start)
    }

    func testCumulativeDriftBeyondRadiusRestartsTimer() {
        var dwell = HoverDwell()
        _ = dwell.pointerMoved(to: CGPoint(x: 0, y: 0), at: at(0))
        XCTAssertEqual(dwell.pointerMoved(to: CGPoint(x: 3, y: 0), at: at(0.1)), .none)
        // 6 points from the anchor: the pointer is drifting, so the timer restarts.
        XCTAssertEqual(dwell.pointerMoved(to: CGPoint(x: 6, y: 0), at: at(0.2)), .none)
        XCTAssertEqual(dwell.pointerMoved(to: CGPoint(x: 6, y: 0), at: at(0.3)), .none)
        XCTAssertEqual(dwell.pointerMoved(to: CGPoint(x: 6, y: 0), at: at(0.45)), .start)
    }

    func testMovementAfterStartReportsRestart() {
        var dwell = HoverDwell()
        _ = dwell.pointerMoved(to: CGPoint(x: 0, y: 0), at: at(0))
        XCTAssertEqual(dwell.pointerMoved(to: CGPoint(x: 0, y: 0), at: at(0.25)), .start)
        XCTAssertEqual(dwell.pointerMoved(to: CGPoint(x: 100, y: 0), at: at(0.3)), .restart)
    }

    func testResetClearsProgress() {
        var dwell = HoverDwell()
        _ = dwell.pointerMoved(to: CGPoint(x: 0, y: 0), at: at(0))
        dwell.reset()
        XCTAssertEqual(dwell.pointerMoved(to: CGPoint(x: 0, y: 0), at: at(0.9)), .none)
        XCTAssertEqual(dwell.pointerMoved(to: CGPoint(x: 0, y: 0), at: at(1.15)), .start)
    }
}
