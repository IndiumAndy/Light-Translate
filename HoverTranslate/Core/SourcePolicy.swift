import Foundation

/// Decides whether the application under the pointer may be read.
///
/// Since 2026-09-17 the user explicitly asked for the tool to work in every
/// application instead of having to add them one by one, so this is an
/// exclusion list and it starts empty: every application is readable while the
/// trigger key is held.
///
/// Two things did not change. An application the user excluded is never read,
/// and a source with no bundle identifier is still refused: it cannot be
/// attributed, so it cannot be matched against the exclusions either.
struct SourcePolicy: Equatable, Sendable {
    let excludedBundleIDs: Set<String>

    func allows(bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return !excludedBundleIDs.contains(bundleID)
    }
}
