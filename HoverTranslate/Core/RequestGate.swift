import Foundation

/// Monotonic generation counter.
///
/// Every new query begins a generation and invalidates the previous one, so an
/// extraction that finishes late can be rejected even when task cancellation
/// could not stop it.
struct RequestGate {
    private var current: UInt64 = 0
    private var valid = false

    mutating func begin() -> UInt64 {
        current += 1
        valid = true
        return current
    }

    mutating func invalidate() {
        valid = false
    }

    func accepts(_ generation: UInt64) -> Bool {
        valid && generation == current
    }
}
