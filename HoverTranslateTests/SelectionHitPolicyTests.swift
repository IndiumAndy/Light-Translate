import XCTest
import CoreGraphics
@testable import HoverTranslate

/// Pure hit-testing rules for "pointer is on the current selection".
///
/// Coordinates are AX screen points (top-left origin) and ranges are UTF-16
/// `CFRange` values, which is what the AX API reports.
final class SelectionHitPolicyTests: XCTestCase {
    private let rect = CGRect(x: 100, y: 200, width: 300, height: 20)
    private let selected = CFRange(location: 10, length: 32)

    func testPointerInsideTheSelectionRectIsAHit() {
        XCTAssertTrue(SelectionHitPolicy.isHit(pointer: CGPoint(x: 250, y: 210),
                                               selectionRect: rect,
                                               pointerRange: CFRange(location: 20, length: 5),
                                               selectedRange: selected))
    }

    func testPointerOutsideTheSelectionRectIsNeverAHit() {
        XCTAssertFalse(SelectionHitPolicy.isHit(pointer: CGPoint(x: 250, y: 260),
                                                selectionRect: rect,
                                                pointerRange: CFRange(location: 20, length: 5),
                                                selectedRange: selected))
    }

    func testEmptySelectionIsNeverAHit() {
        XCTAssertFalse(SelectionHitPolicy.isHit(pointer: CGPoint(x: 250, y: 210),
                                                selectionRect: rect,
                                                pointerRange: CFRange(location: 0, length: 4),
                                                selectedRange: CFRange(location: 0, length: 0)))
    }

    /// The union rect of a multi-line selection covers text that is not
    /// selected, so the index test has to reject that point.
    func testIndexTestRejectsAPointInsideTheUnionRectButOutsideTheSelection() {
        XCTAssertFalse(SelectionHitPolicy.isHit(pointer: CGPoint(x: 250, y: 210),
                                                selectionRect: rect,
                                                pointerRange: CFRange(location: 60, length: 5),
                                                selectedRange: selected))
    }

    /// An app that does not report `AXRangeForPosition` leaves geometry as the
    /// only evidence; degrade honestly instead of guessing an index.
    func testGeometryAloneDecidesWhenTheAppReportsNoRange() {
        XCTAssertTrue(SelectionHitPolicy.isHit(pointer: CGPoint(x: 250, y: 210),
                                               selectionRect: rect,
                                               pointerRange: nil,
                                               selectedRange: selected))
        XCTAssertFalse(SelectionHitPolicy.isHit(pointer: CGPoint(x: 250, y: 260),
                                                selectionRect: rect,
                                                pointerRange: nil,
                                                selectedRange: selected))
    }

    func testToleranceOnlyCoversPixelRounding() {
        XCTAssertTrue(SelectionHitPolicy.isInside(CGPoint(x: 99, y: 210), rect: rect))
        XCTAssertFalse(SelectionHitPolicy.isInside(CGPoint(x: 96, y: 210), rect: rect))
    }

    func testAdjacentRangesDoNotOverlap() {
        XCTAssertFalse(SelectionHitPolicy.overlaps(CFRange(location: 42, length: 3), selectedRange: selected))
        XCTAssertFalse(SelectionHitPolicy.overlaps(CFRange(location: 7, length: 3), selectedRange: selected))
        XCTAssertTrue(SelectionHitPolicy.overlaps(CFRange(location: 40, length: 3), selectedRange: selected))
    }
}
