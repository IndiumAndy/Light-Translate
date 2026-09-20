import Foundation

/// What to translate. Holds no source window, file path, screenshot or
/// Accessibility object, so it can be logged or queued without leaking context.
struct TranslationRequest: Equatable, Sendable {
    /// The text the user is pointing at, or the text they pasted.
    let text: String
    /// Optional short surrounding text. Never a window title or file path.
    let context: String
    let mode: QueryMode
    let targetLanguage: String

    init(text: String,
         context: String = "",
         mode: QueryMode = .word,
         targetLanguage: String = "zh-Hans") {
        self.text = text
        self.context = context
        self.mode = mode
        self.targetLanguage = targetLanguage
    }
}

/// A finished translation plus the identity of the thing that produced it. The
/// English shown to the user always comes from the local extraction snapshot,
/// never from the model restating the source.
struct TranslationResult: Equatable, Sendable {
    let text: String
    let model: String
    let provider: String
    let promptVersion: Int
}

/// Translation boundary. Implementations must classify every failure into
/// `TranslationFailure` and must never surface a raw response body.
protocol TranslationService: Sendable {
    /// `model` is the configured model id. It comes from the settings layer, so
    /// an adapter asks for exactly the model the user chose instead of keeping an
    /// alias of its own that the settings could not influence.
    func translate(_ request: TranslationRequest,
                   apiKey: String,
                   model: String) async throws -> TranslationResult
}
