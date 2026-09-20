import Foundation
import os

/// Why a saved-entries file could not be used.
enum LearningStoreError: Error, Equatable {
    /// The file exists but is not the list this app writes. It is left exactly
    /// as it is; only the user decides whether to clear it.
    case unreadable
}

/// The user's saved entries, in one JSON file.
///
/// Application Support in the app and a temporary directory in tests. Every
/// write is atomic, and a file that cannot be decoded is never overwritten, so a
/// damaged file can never turn into silent data loss.
///
/// It is a value type with no shared mutable state: the app uses it from the
/// main actor, tests use it from their own temporary directories.
struct LearningStore: Sendable {
    static let fileName = "SavedEntries.json"

    /// The app's own file under Application Support. The app is not sandboxed,
    /// so this is the user's real ~/Library/Application Support/HoverTranslate.
    static func applicationSupport() -> LearningStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return LearningStore(directory: base.appendingPathComponent("HoverTranslate", isDirectory: true))
    }

    let directory: URL
    private let log = Logger(subsystem: "com.atat.HoverTranslate", category: "learning")

    init(directory: URL) {
        self.directory = directory
    }

    var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    func all() throws -> [SavedEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else { return [] }
            return try Self.makeDecoder().decode([SavedEntry].self, from: data)
        } catch {
            // Only that decoding failed: never the contents, never the path.
            log.debug("saved entries could not be decoded")
            throw LearningStoreError.unreadable
        }
    }

    /// Appends one entry. Reading first is deliberate: a file that cannot be
    /// read must not be replaced.
    func save(_ entry: SavedEntry) throws {
        var entries = try all()
        entries.append(entry)
        try write(entries)
    }

    func remove(id: UUID) throws {
        var entries = try all()
        entries.removeAll { $0.id == id }
        try write(entries)
    }

    /// The explicit recovery path: replaces the file with an empty list, which
    /// is the only operation allowed to overwrite an unreadable one.
    func removeAll() throws {
        try write([])
    }

    private func write(_ entries: [SavedEntry]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Atomic: a crash mid-write leaves the previous file intact.
        try Self.makeEncoder().encode(entries).write(to: fileURL, options: .atomic)
    }

    // One coder per call: JSONEncoder and JSONDecoder are reference types that
    // are not safe to share between threads.
    //
    // Dates keep foundation's full-precision encoding instead of ISO-8601, which
    // drops fractional seconds: an entry that came back from disk must still be
    // the same entry, and two saves in the same second must not become equal.
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }
}
