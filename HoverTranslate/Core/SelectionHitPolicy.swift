import CoreGraphics

/// Whether the pointer is on "the selection that is already there".
///
/// The three inputs are independent and there is exactly one combination rule:
/// geometry has to hit, and when the application can report which character is
/// under the pointer, that index has to hit as well. Kept free of Accessibility
/// so the rule can be pinned by tests without a running application.
///
/// Units: `pointer` and `selectionRect` are AX screen points (origin at the
/// top-left of the primary display, the same space `CoordinateMapper` and the hit
/// path use); ranges are UTF-16 `CFRange` values, which is what AX reports.
enum SelectionHitPolicy {
    /// Initial design value, not a measured one: it only covers pixel rounding,
    /// it is not wide enough to reach neighbouring characters.
    static let tolerance: CGFloat = 2

    /// The boundary counts as inside, so a pointer resting on the last pixel of
    /// the selection is still a hit.
    static func isInside(_ point: CGPoint, rect: CGRect, tolerance: CGFloat = tolerance) -> Bool {
        rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    }

    /// Whether two UTF-16 ranges share a character. An empty selection is never
    /// a hit, and ranges that merely touch are not an overlap: the selection
    /// 10..<42 does not contain 42..<45.
    static func overlaps(_ pointerRange: CFRange, selectedRange: CFRange) -> Bool {
        guard pointerRange.length > 0, selectedRange.length > 0 else { return false }
        return pointerRange.location < selectedRange.location + selectedRange.length
            && selectedRange.location < pointerRange.location + pointerRange.length
    }

    /// The one combination rule. `pointerRange == nil` means the application
    /// does not report a range for a position, and geometry is then the only
    /// evidence there is.
    static func isHit(pointer: CGPoint,
                      selectionRect: CGRect,
                      pointerRange: CFRange?,
                      selectedRange: CFRange,
                      tolerance: CGFloat = tolerance) -> Bool {
        guard selectedRange.length > 0,
              isInside(pointer, rect: selectionRect, tolerance: tolerance) else { return false }
        guard let pointerRange else { return true }
        return overlaps(pointerRange, selectedRange: selectedRange)
    }
}
