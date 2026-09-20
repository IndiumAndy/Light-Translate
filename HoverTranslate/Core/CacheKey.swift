import Foundation

/// Identity of one cached translation.
///
/// Context and model are part of the identity on purpose: "charge" in a battery
/// sentence and "charge" in a service-charge sentence are different answers,
/// and a cached answer must never be reused after the model or prompt changes.
struct CacheKey: Hashable, Sendable {
    let mode: QueryMode
    let text: String
    let context: String
    let targetLanguage: String
    let provider: String
    let model: String
    let promptVersion: Int

    init(mode: QueryMode,
         text: String,
         context: String = "",
         targetLanguage: String = "zh-Hans",
         provider: String = "deepseek",
         model: String = "deepseek-flash",
         promptVersion: Int = TranslationRequestBuilder.promptVersion) {
        self.mode = mode
        self.text = text
        self.context = context
        self.targetLanguage = targetLanguage
        self.provider = provider
        self.model = model
        self.promptVersion = promptVersion
    }
}
