import XCTest
@testable import HoverTranslate

final class TranslationCacheTests: XCTestCase {
    private let excluded: Set<String> = ["com.example.reader"]

    private func key(text: String = "charge",
                     context: String = "battery charge",
                     mode: QueryMode = .word,
                     model: String = "model-a",
                     promptVersion: Int = 1) -> CacheKey {
        CacheKey(mode: mode,
                 text: text,
                 context: context,
                 targetLanguage: "zh-Hans",
                 provider: "deepseek",
                 model: model,
                 promptVersion: promptVersion)
    }

    private func result(_ text: String) -> TranslationResult {
        TranslationResult(text: text, model: "model-a", provider: "deepseek", promptVersion: 1)
    }

    /// Injectable clock: tests never wait on wall-clock time.
    final class FakeClock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Date
        init(_ start: Date) { value = start }
        func now() -> Date {
            lock.lock(); defer { lock.unlock() }
            return value
        }
        func advance(_ seconds: TimeInterval) {
            lock.lock(); defer { lock.unlock() }
            value = value.addingTimeInterval(seconds)
        }
    }

    // MARK: - Identity

    func testContextAndModelArePartOfIdentity() {
        XCTAssertNotEqual(key(), key(context: "service charge"))
        XCTAssertNotEqual(key(), key(model: "model-b"))
        XCTAssertNotEqual(key(), key(mode: .selection))
        XCTAssertNotEqual(key(), key(text: "charges"))
        XCTAssertNotEqual(key(), key(promptVersion: 2))
        XCTAssertEqual(key(), key())
    }

    // MARK: - Behaviour

    func testInsertThenGetReturnsTheSameResult() async {
        let cache = TranslationCache()
        await cache.insert(result("收费"), for: key(), sourceBundleID: "com.example.reader")
        let hit = await cache.get(key(), sourceBundleID: "com.example.reader", excludedBundleIDs: [])
        XCTAssertEqual(hit?.text, "收费")
    }

    func testContextsDoNotContaminateEachOther() async {
        let cache = TranslationCache()
        await cache.insert(result("电池充电"), for: key(context: "battery charge"), sourceBundleID: "com.example.reader")
        await cache.insert(result("服务费"), for: key(context: "service charge"), sourceBundleID: "com.example.reader")

        let battery = await cache.get(key(context: "battery charge"), sourceBundleID: "com.example.reader", excludedBundleIDs: [])
        let service = await cache.get(key(context: "service charge"), sourceBundleID: "com.example.reader", excludedBundleIDs: [])
        XCTAssertEqual(battery?.text, "电池充电")
        XCTAssertEqual(service?.text, "服务费")
    }

    func testEntryExpiresAfterTheTTL() async {
        let clock = FakeClock(Date(timeIntervalSince1970: 5_000))
        let cache = TranslationCache(ttl: 600, now: { clock.now() })
        await cache.insert(result("收费"), for: key(), sourceBundleID: "com.example.reader")

        clock.advance(599)
        let fresh = await cache.get(key(), sourceBundleID: "com.example.reader", excludedBundleIDs: [])
        XCTAssertEqual(fresh?.text, "收费")

        clock.advance(2)
        let expired = await cache.get(key(), sourceBundleID: "com.example.reader", excludedBundleIDs: [])
        XCTAssertNil(expired)
        let size = await cache.count
        XCTAssertEqual(size, 0, "an expired entry is dropped, not kept forever")
    }

    func testCapacityEvictsTheOldestEntry() async {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000))
        let cache = TranslationCache(capacity: 2, now: { clock.now() })
        await cache.insert(result("one"), for: key(text: "one"), sourceBundleID: "com.example.reader")
        clock.advance(1)
        await cache.insert(result("two"), for: key(text: "two"), sourceBundleID: "com.example.reader")
        clock.advance(1)
        await cache.insert(result("three"), for: key(text: "three"), sourceBundleID: "com.example.reader")

        let size = await cache.count
        XCTAssertEqual(size, 2)
        let evicted = await cache.get(key(text: "one"), sourceBundleID: "com.example.reader", excludedBundleIDs: [])
        let kept = await cache.get(key(text: "three"), sourceBundleID: "com.example.reader", excludedBundleIDs: [])
        XCTAssertNil(evicted)
        XCTAssertEqual(kept?.text, "three")
    }

    // MARK: - Policy

    /// v0.5: the list is exclusions. An excluded source must not read an answer,
    /// an unattributed one must not either, and everything else may.
    func testAnExcludedOrUnknownSourceCannotReadTheCache() async {
        let cache = TranslationCache()
        await cache.insert(result("收费"), for: key(), sourceBundleID: "com.example.reader")

        let excludedSource = await cache.get(key(), sourceBundleID: "com.example.reader", excludedBundleIDs: excluded)
        let unknown = await cache.get(key(), sourceBundleID: nil, excludedBundleIDs: [])
        let stillReadable = await cache.get(key(), sourceBundleID: "com.example.reader", excludedBundleIDs: [])
        XCTAssertNil(excludedSource)
        XCTAssertNil(unknown)
        XCTAssertEqual(stillReadable?.text, "收费", "nothing is excluded, so the entry is readable")
    }

    func testEntriesForExcludedSourcesAreDropped() async {
        let cache = TranslationCache()
        await cache.insert(result("收费"), for: key(), sourceBundleID: "com.example.reader")
        await cache.insert(result("费用"), for: key(text: "fee"), sourceBundleID: "com.example.other")
        await cache.insert(result("无人认领"), for: key(text: "orphan"), sourceBundleID: nil)

        // The user excluded com.example.reader.
        await cache.removeAll(sourcesExcludedBy: excluded)

        let removed = await cache.get(key(), sourceBundleID: "com.example.reader", excludedBundleIDs: [])
        XCTAssertNil(removed)
        let size = await cache.count
        XCTAssertEqual(size, 1, "the excluded entry and the unattributable one are dropped; the rest stays")
        let kept = await cache.get(key(text: "fee"), sourceBundleID: "com.example.other", excludedBundleIDs: [])
        XCTAssertEqual(kept?.text, "费用")
    }

    func testEntriesForSourcesStillIncludedSurviveAChange() async {
        let cache = TranslationCache()
        await cache.insert(result("收费"), for: key(), sourceBundleID: "com.example.reader")
        await cache.insert(result("费用"), for: key(text: "fee"), sourceBundleID: "com.example.other")

        // com.example.other was excluded; com.example.reader was not.
        await cache.removeAll(sourcesExcludedBy: ["com.example.other"])

        let kept = await cache.get(key(), sourceBundleID: "com.example.reader", excludedBundleIDs: [])
        XCTAssertEqual(kept?.text, "收费")
        let size = await cache.count
        XCTAssertEqual(size, 1)
    }

    func testRemoveAllClearsEverything() async {
        let cache = TranslationCache()
        await cache.insert(result("收费"), for: key(), sourceBundleID: "com.example.reader")
        await cache.removeAll()
        let size = await cache.count
        XCTAssertEqual(size, 0)
    }
}
