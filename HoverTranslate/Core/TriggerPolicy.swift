import Foundation

/// Query modes the app can run. v0.1 implements `word` only; the remaining
/// cases exist so later phases do not have to rename the enum.
enum QueryMode: String, Equatable, Sendable {
    case word
    case sentence
    case selection
    case explanation
}

/// Pure decision: should the configured trigger key start a query?
///
/// The event layer tracks the left and right Option keys separately, so
/// releasing one while the other is still held stops the configured mode
/// instead of appearing "sticky".
enum TriggerPolicy {
    static func mode(rightOption: Bool,
                     leftOption: Bool,
                     control: Bool,
                     enabled: Bool,
                     useRightOption: Bool) -> QueryMode? {
        guard enabled else { return nil }
        let triggerHeld = useRightOption ? rightOption : leftOption
        guard triggerHeld else { return nil }
        // v0.3: holding Control as well asks for the whole sentence instead of
        // the word. Releasing Control mid-gesture downgrades again, which is a
        // mode switch the coordinator has to invalidate. Shift is deliberately
        // not used: it is the key people hold while adjusting a selection.
        return control ? .sentence : .word
    }
}
