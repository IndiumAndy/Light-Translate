import Foundation

/// What may be sent for translation.
///
/// The limit is counted in Unicode characters, not UTF-16 code units or bytes,
/// so a Chinese or emoji-heavy selection is measured the way a person counts.
/// Over-long text is refused outright: silently dropping the second half of a
/// selection would translate something the user never chose.
enum TextInputPolicy {
    /// Initial value from the design, shared with v0.3 sentence mode.
    static let defaultLimit = 4000

    static func isAllowed(_ text: String, limit: Int) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.count <= limit
    }
}
