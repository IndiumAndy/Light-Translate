import Foundation

/// Things that can go wrong while translating. Deliberately separate from
/// `ExtractionFailure`: a translation problem must never be reported as a
/// text-extraction problem, and vice versa.
/// The case names are also the log category, which is why they are stable and
/// deliberately free of any user text.
enum TranslationFailure: String, Error, Equatable, Sendable {
    /// The user has not entered an API key yet. Not an error to apologise for:
    /// the word card still shows the original text.
    case apiKeyMissing
    case invalidKey
    /// Reserved for HTTP 402. v0.2 does not map any status code here on
    /// purpose: assuming an account is out of credit would tell the user the
    /// wrong thing to fix, so 402 is reported as `invalidResponse` instead.
    case insufficientBalance
    case rateLimited
    case network
    case timeout
    case invalidResponse
    /// `finish_reason` was `length`: the output was cut off and must never be
    /// presented as a finished translation.
    case truncatedOutput
    case cancelled
    case configuration

    var message: String {
        switch self {
        case .apiKeyMissing: return "add a DeepSeek API key in Settings to see Chinese"
        case .invalidKey: return "the API key was rejected"
        case .insufficientBalance: return "the DeepSeek account has no credit"
        case .rateLimited: return "DeepSeek is rate limiting; try again later"
        case .network: return "the request could not reach DeepSeek"
        case .timeout: return "DeepSeek did not answer in time"
        case .invalidResponse: return "DeepSeek returned an unusable response"
        case .truncatedOutput: return "the translation was cut off; select less text"
        case .cancelled: return "the request was cancelled"
        case .configuration: return "the translation request is not configured"
        }
    }
}
