import CoreGraphics
import Foundation

/// How much of a control the resolved text covers.
enum ExtractionScope: String, Equatable, Sendable {
    /// An exact word, verified to contain the pointer position.
    case word
    /// The whole label of a short control; never a "precise word".
    case label
    case sentence
    case selection
}

enum ExtractionSource: String, Equatable, Sendable {
    case accessibility
    case ocr
    case manual
}

enum ExtractionCompleteness: String, Equatable, Sendable {
    case complete
    case partial
}

/// Value snapshot of one extraction. No Accessibility object is ever stored
/// here, so the snapshot can cross actor boundaries safely.
struct ExtractionSnapshot: Equatable, Sendable {
    let text: String
    let context: String?
    let scope: ExtractionScope
    let completeness: ExtractionCompleteness
    let source: ExtractionSource
    let sourcePID: pid_t
    let sourceBundleID: String?
    /// Screen rect of the hit text in AppKit coordinates, when the source
    /// reported one.
    let wordFrame: CGRect?
    let generation: UInt64

    /// How the text was obtained decides the translation mode, so the request
    /// is built from the snapshot instead of from a second guess.
    var mode: QueryMode {
        switch scope {
        case .selection: return .selection
        case .sentence: return .sentence
        case .word, .label: return .word
        }
    }
}

/// Everything the extractor needs. Contains no Accessibility objects.
struct ExtractionRequest: Equatable, Sendable {
    /// AppKit screen coordinates of the pointer.
    let point: CGPoint
    let sourcePID: pid_t
    let sourceBundleID: String?
    /// The on-screen window the pointer was confirmed to be over, as the window
    /// list reported it. The screenshot fallback captures exactly this window
    /// instead of deciding a second time which window belongs to the source, and
    /// without it there is no area any implementation may capture.
    var sourceWindowID: CGWindowID? = nil
    let generation: UInt64
    let mode: QueryMode
}

/// The case names are also the log category, which is why they are stable and
/// deliberately free of any user text.
enum ExtractionFailure: String, Error, Equatable {
    case permissionDenied
    /// The application under the pointer is excluded in this app's settings.
    /// Kept separate from `permissionDenied` so the menu never sends the user to
    /// System Settings for a problem this app's own settings solve.
    case appNotAllowed
    case unknownOwner
    case blockedSensitive
    case positionUnresolved
    /// The control reports no position to text mapping at all. This is the one
    /// technical limitation that may justify the OCR fallback; every policy
    /// failure above never does.
    case notSupported
    case noText
    case timeout

    var message: String {
        switch self {
        case .permissionDenied: return "accessibility permission is required"
        case .appNotAllowed: return "this application is excluded in Settings"
        case .unknownOwner: return "the pointed window belongs to another application"
        case .blockedSensitive: return "the control is protected"
        case .positionUnresolved: return "no exact text at this position"
        case .notSupported: return "this control does not report text positions"
        case .noText: return "no readable text at this position"
        case .timeout: return "the application did not answer in time"
        }
    }
}

/// Extraction boundary. Implementations return value snapshots only.
protocol TextExtracting: Sendable {
    func extract(_ request: ExtractionRequest) async throws -> ExtractionSnapshot
}
