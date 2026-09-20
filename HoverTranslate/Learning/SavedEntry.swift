import Foundation

/// One entry the user chose to keep.
///
/// Only what was on the card when Save was pressed: the English that was
/// pointed at, the translation that was shown and the short context that was
/// already part of the request. Never a window title, a file path, an
/// application name or a screenshot.
struct SavedEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    /// The English text the entry was made from.
    let source: String
    /// The Chinese that was on the card when the user pressed Save.
    let translation: String
    /// The short context the entry was seen in. It is part of the entry, so the
    /// same word in two contexts is two entries rather than one.
    let context: String
    let createdAt: Date

    init(id: UUID = UUID(),
         source: String,
         translation: String,
         context: String,
         createdAt: Date = Date()) {
        self.id = id
        self.source = source
        self.translation = translation
        self.context = context
        self.createdAt = createdAt
    }
}
