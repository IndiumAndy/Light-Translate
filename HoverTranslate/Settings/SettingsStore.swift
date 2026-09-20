import Foundation

/// Preferences that are not sensitive.
///
/// API keys never belong here: they are user-entered in v0.2 and stored in a
/// dedicated Keychain item, never in UserDefaults, source or logs.
@MainActor
final class SettingsStore: ObservableObject, SettingsReading {
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.enabled) }
    }

    @Published var useRightOption: Bool {
        didSet { defaults.set(useRightOption, forKey: Keys.useRightOption) }
    }

    /// Applications the user does not want read. It starts empty, so every
    /// application is readable; the user only ever adds an app here to exclude
    /// it.
    @Published private(set) var excludedBundleIDs: Set<String> {
        didSet { defaults.set(excludedBundleIDs.sorted(), forKey: Keys.excluded) }
    }

    /// v0.3: the screenshot fallback. Off by default, like every other read
    /// permission this app adds.
    @Published var isOCRFallbackEnabled: Bool {
        didSet { defaults.set(isOCRFallbackEnabled, forKey: Keys.ocrFallback) }
    }

    /// v0.4: index into the selection-shortcut presets. Stored as a number so
    /// this store keeps no AppKit types; an out-of-range value falls back to the
    /// first preset where it is read.
    @Published var selectionShortcutIndex: Int {
        didSet { defaults.set(selectionShortcutIndex, forKey: Keys.selectionShortcut) }
    }

    private enum Keys {
        static let enabled = "HoverTranslate.isEnabled"
        static let useRightOption = "HoverTranslate.useRightOption"
        static let excluded = "HoverTranslate.excludedBundleIDs"
        /// The v0.1-v0.4 allow list. Deliberately not reused and not migrated:
        /// its contents meant "only these applications", and reading them as
        /// exclusions would silently block exactly the applications the user
        /// had chosen to read.
        static let legacyAllowed = "HoverTranslate.allowedBundleIDs"
        static let ocrFallback = "HoverTranslate.ocrFallbackEnabled"
        static let selectionShortcut = "HoverTranslate.selectionShortcutIndex"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? false
        self.useRightOption = defaults.object(forKey: Keys.useRightOption) as? Bool ?? true
        self.excludedBundleIDs = Set(defaults.stringArray(forKey: Keys.excluded) ?? [])
        self.isOCRFallbackEnabled = defaults.object(forKey: Keys.ocrFallback) as? Bool ?? false
        self.selectionShortcutIndex = defaults.object(forKey: Keys.selectionShortcut) as? Int ?? 0
    }

    func exclude(bundleID: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        excludedBundleIDs.insert(trimmed)
    }

    func stopExcluding(bundleID: String) {
        excludedBundleIDs.remove(bundleID)
    }
}
