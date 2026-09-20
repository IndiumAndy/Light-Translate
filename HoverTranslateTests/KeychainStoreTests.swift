import XCTest
@testable import HoverTranslate

/// Exercises the real Keychain but only inside a test-only namespace, and
/// removes every item it creates. Keys here are synthetic.
final class KeychainStoreTests: XCTestCase {
    private let service = "com.atat.HoverTranslate.tests"
    private let store = KeychainStore(service: "com.atat.HoverTranslate.tests")
    private let account = "synthetic-test-key"

    override func tearDown() {
        try? store.deleteSecret(for: account)
        super.tearDown()
    }

    func testMissingAccountReadsAsNil() {
        XCTAssertNil(store.secret(for: account))
    }

    func testRoundTripReplaceAndDelete() throws {
        try store.setSecret("sk-synthetic-one", for: account)
        XCTAssertEqual(store.secret(for: account), "sk-synthetic-one")

        // Replacing must not fail with errSecDuplicateItem.
        try store.setSecret("sk-synthetic-two", for: account)
        XCTAssertEqual(store.secret(for: account), "sk-synthetic-two")

        try store.deleteSecret(for: account)
        XCTAssertNil(store.secret(for: account))
    }

    func testSettingNilOrBlankDeletes() throws {
        try store.setSecret("sk-synthetic", for: account)
        try store.setSecret(nil, for: account)
        XCTAssertNil(store.secret(for: account))

        try store.setSecret("   ", for: account)
        XCTAssertNil(store.secret(for: account))
    }

    func testDeletingAMissingItemIsNotAnError() {
        XCTAssertNoThrow(try store.deleteSecret(for: "never-created"))
    }

    func testItemsAreNamespacedByService() throws {
        try store.setSecret("sk-scoped", for: account)
        XCTAssertNil(KeychainStore(service: service + ".other").secret(for: account))
    }
}
