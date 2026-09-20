import Foundation

/// In-memory translation cache: at most `capacity` entries, each valid for
/// `ttl`. Nothing is written to disk, so quitting the app forgets everything.
///
/// An actor rather than a locked dictionary: the coordinator is main-actor and
/// the network results arrive from a task, and neither should block the other.
actor TranslationCache {
    struct Entry: Sendable {
        let result: TranslationResult
        let storedAt: Date
        /// The application the text came from. Cache reads are still subject to
        /// the exclusion list, so a cached answer cannot outlive a block.
        let sourceBundleID: String?
    }

    private var entries: [CacheKey: Entry] = [:]
    private let capacity: Int
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date

    init(capacity: Int = 256,
         ttl: TimeInterval = 600,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.capacity = max(1, capacity)
        self.ttl = ttl
        self.now = now
    }

    var count: Int { entries.count }

    func get(_ key: CacheKey,
             sourceBundleID: String?,
             excludedBundleIDs: Set<String>) -> TranslationResult? {
        // Policy first: an excluded source must not read an answer it could not
        // have obtained right now.
        guard SourcePolicy(excludedBundleIDs: excludedBundleIDs).allows(bundleID: sourceBundleID) else {
            return nil
        }
        guard let entry = entries[key] else { return nil }
        guard SourcePolicy(excludedBundleIDs: excludedBundleIDs).allows(bundleID: entry.sourceBundleID) else {
            return nil
        }
        guard now().timeIntervalSince(entry.storedAt) < ttl else {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry.result
    }

    func insert(_ result: TranslationResult, for key: CacheKey, sourceBundleID: String?) {
        if entries.count >= capacity, entries[key] == nil {
            evictOldest()
        }
        entries[key] = Entry(result: result, storedAt: now(), sourceBundleID: sourceBundleID)
    }

    /// Called when the exclusion list changes, the key is deleted, or the
    /// session locks. Losing a cache entry only costs one request.
    func removeAll() {
        entries.removeAll()
    }

    /// Drops every entry whose source the user has now excluded. Entries with no
    /// recorded source (manual entry) are dropped too, because they can never be
    /// attributed and therefore can never be read back.
    func removeAll(sourcesExcludedBy excludedBundleIDs: Set<String>) {
        var survivors: [CacheKey: Entry] = [:]
        for (key, entry) in entries {
            guard let bundle = entry.sourceBundleID, !excludedBundleIDs.contains(bundle) else { continue }
            survivors[key] = entry
        }
        entries = survivors
    }

    private func evictOldest() {
        guard let oldest = entries.min(by: { $0.value.storedAt < $1.value.storedAt }) else { return }
        entries.removeValue(forKey: oldest.key)
    }
}

