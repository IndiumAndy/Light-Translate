import Foundation

/// Everything the coordinator needs to talk to a translation provider.
///
/// The key is read on demand from the Keychain and is never published on an
/// ObservableObject, so it cannot end up in a view's debugDescription.
struct TranslationConfiguration: Equatable, Sendable {
    let provider: String
    let model: String
    let apiKey: String
    let isConfigured: Bool

    static let unconfigured = TranslationConfiguration(provider: "deepseek",
                                                       model: TranslationSettingsStore.defaultModel,
                                                       apiKey: "",
                                                       isConfigured: false)
}

/// Non-sensitive translation preferences. The API key is not here.
@MainActor
final class TranslationSettingsStore: ObservableObject {
    nonisolated static let defaultModel = "deepseek-flash"
    /// The only model ids the API currently documents. The field stays editable
    /// so a renamed model does not require a rebuild.
    nonisolated static let knownModels = ["deepseek-flash", "deepseek-v4-pro"]

    @Published var model: String {
        didSet {
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed.isEmpty ? Self.defaultModel : trimmed, forKey: Keys.model)
        }
    }

    /// True while a translation hint may be attempted at all.
    @Published var isTranslationEnabled: Bool {
        didSet { defaults.set(isTranslationEnabled, forKey: Keys.enabled) }
    }

    private enum Keys {
        static let model = "HoverTranslate.translation.model"
        static let enabled = "HoverTranslate.translation.enabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.model = defaults.string(forKey: Keys.model) ?? Self.defaultModel
        self.isTranslationEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
    }

    func configuration(secrets: SecretStoring) -> TranslationConfiguration {
        let key = secrets.secret(for: KeychainStore.deepSeekAPIKeyAccount) ?? ""
        return TranslationConfiguration(provider: "deepseek",
                                        model: model,
                                        apiKey: key,
                                        isConfigured: isTranslationEnabled && !key.isEmpty)
    }
}
