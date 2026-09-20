import XCTest
@testable import HoverTranslate

final class TextInputPolicyTests: XCTestCase {
    func testEmptyAndOversizedTextRejected() {
        XCTAssertFalse(TextInputPolicy.isAllowed("  \n ", limit: 4000))
        XCTAssertFalse(TextInputPolicy.isAllowed("", limit: 4000))
        XCTAssertFalse(TextInputPolicy.isAllowed(String(repeating: "x", count: 4001), limit: 4000))
        XCTAssertTrue(TextInputPolicy.isAllowed("Open Settings", limit: 4000))
    }

    func testExactlyAtTheLimitIsAllowed() {
        XCTAssertTrue(TextInputPolicy.isAllowed(String(repeating: "x", count: 4000), limit: 4000))
    }

    func testLimitCountsCharactersNotUTF16Units() {
        // 3000 emoji are 6000 UTF-16 units but 3000 characters.
        let emoji = String(repeating: "😀", count: 3000)
        XCTAssertTrue(TextInputPolicy.isAllowed(emoji, limit: 4000))

        let composed = String(repeating: "e\u{301}", count: 4000)
        XCTAssertTrue(TextInputPolicy.isAllowed(composed, limit: 4000))
    }

    func testOverlongTextIsNotSilentlyTrimmed() {
        let overlong = String(repeating: "x", count: 5000)
        XCTAssertFalse(TextInputPolicy.isAllowed(overlong, limit: 4000),
                       "the caller must refuse, not send a prefix")
    }
}
