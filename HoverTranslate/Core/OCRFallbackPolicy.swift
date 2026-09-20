import Foundation

/// v0.3: whether a failed Accessibility read may be retried from a screenshot.
///
/// The fallback is deliberately narrow. A policy refusal (a protected control, a
/// denied permission, an application the user excluded, an unowned
/// window) is a decision, not a limitation, so capturing the screen would
/// bypass the very rule that produced the failure. Only a technical limitation
/// qualifies, and only with the user's switch, a granted capture permission and
/// a source window that was already confirmed.
enum OCRFallbackPolicy {
    /// Failures that mean "the control cannot tell us" rather than "we must not".
    static let technicalFailures: Set<ExtractionFailure> = [.noText, .notSupported, .positionUnresolved]

    static func allows(_ failure: ExtractionFailure,
                       userEnabled: Bool,
                       captureAuthorized: Bool,
                       sourceConfirmed: Bool) -> Bool {
        guard userEnabled, captureAuthorized, sourceConfirmed else { return false }
        return technicalFailures.contains(failure)
    }

    /// Shown while a capture is waiting for the interval. Waiting is not a
    /// failure, and a failure is not silent.
    static let waitingStatus = "recognizing…"
}

/// v0.3: at most one capture per interval.
///
/// Initial value from the design, not measured. Even when every prerequisite is
/// satisfied, a moving pointer must not turn into continuous screen recording.
struct OCRRateLimiter {
    static let minimumInterval: TimeInterval = 0.8

    private var lastStart: Date?

    /// The earliest moment a capture may start, or nil when it may start now.
    ///
    /// A rate limit is a "when", not a "no": the caller can wait for this instant
    /// instead of treating the refusal as the end of the query.
    func earliestStart(now: Date) -> Date? {
        guard let lastStart else { return nil }
        let earliest = lastStart.addingTimeInterval(Self.minimumInterval)
        return now < earliest ? earliest : nil
    }

    /// Consumes a slot when one is available. A refused call records nothing.
    mutating func takeSlot(now: Date) -> Bool {
        guard earliestStart(now: now) == nil else { return false }
        lastStart = now
        return true
    }

    mutating func reset() { lastStart = nil }
}
