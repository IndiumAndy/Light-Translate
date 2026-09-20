import CoreGraphics
import Foundation

/// Decides when a held trigger key plus a resting pointer should start a query.
///
/// The pointer must stay within `radius` screen points of an anchor for `dwell`
/// seconds. Movement beyond the radius moves the anchor and restarts the timer,
/// so a slow drift across text can never be mistaken for a stationary pointer.
struct HoverDwell {
    enum Step: Equatable {
        /// Nothing to do.
        case none
        /// The pointer rested long enough: a query may start.
        case start
        /// The pointer left the anchor while a query was already started, so the
        /// previous candidate is stale.
        case restart
    }

    let dwell: TimeInterval
    let radius: CGFloat

    private var anchor: CGPoint?
    private var anchoredAt: Date?
    private var started = false

    init(dwell: TimeInterval = 0.25, radius: CGFloat = 4) {
        self.dwell = dwell
        self.radius = radius
    }

    var hasStarted: Bool { started }

    mutating func pointerMoved(to point: CGPoint, at now: Date) -> Step {
        guard let currentAnchor = anchor, let anchoredAt else {
            anchor = point
            self.anchoredAt = now
            started = false
            return .none
        }

        let distance = hypot(point.x - currentAnchor.x, point.y - currentAnchor.y)
        if distance > radius {
            let wasStarted = started
            anchor = point
            self.anchoredAt = now
            started = false
            return wasStarted ? .restart : .none
        }

        if !started, now.timeIntervalSince(anchoredAt) >= dwell {
            started = true
            return .start
        }
        return .none
    }

    mutating func reset() {
        anchor = nil
        anchoredAt = nil
        started = false
    }
}
