import XCTest
@testable import HoverTranslate

final class TextResolverTests: XCTestCase {
    func testEmojiBeforeWordDoesNotShiftHit() {
        let text = "🙂 Open Settings."
        let offset = (text as NSString).range(of: "Settings").location + 2
        XCTAssertEqual(TextResolver.word(in: text,
            atUTF16Offset: offset), "Settings")
    }
    func testWhitespaceIsNotNearestWord() {
        XCTAssertNil(TextResolver.word(in: "Open Settings", atUTF16Offset: 4))
    }
    func testInvalidOffsetIsSafe() {
        XCTAssertNil(TextResolver.word(in: "Open", atUTF16Offset: -1))
        XCTAssertNil(TextResolver.word(in: "Open", atUTF16Offset: 99))
    }

    func testFirstAndLastCharacterOfWordResolve() {
        let text = "Open Settings"
        XCTAssertEqual(TextResolver.word(in: text, atUTF16Offset: 0), "Open")
        XCTAssertEqual(TextResolver.word(in: text, atUTF16Offset: 3), "Open")
        XCTAssertEqual(TextResolver.word(in: text, atUTF16Offset: 5), "Settings")
        XCTAssertEqual(TextResolver.word(in: text, atUTF16Offset: 12), "Settings")
    }

    func testPunctuationAndLineBreaksReturnNil() {
        XCTAssertNil(TextResolver.word(in: "Open, Settings.\n", atUTF16Offset: 4))
        XCTAssertEqual(TextResolver.word(in: "Open, Settings.\n", atUTF16Offset: 6), "Settings")
        XCTAssertNil(TextResolver.word(in: "Open, Settings.\n", atUTF16Offset: 14))
        XCTAssertNil(TextResolver.word(in: "Open, Settings.\n", atUTF16Offset: 15))
    }

    func testInternalApostropheAndHyphenStayOneWord() {
        let text = "Don't re-open the file"
        XCTAssertEqual(TextResolver.word(in: text, atUTF16Offset: 1), "Don't")
        XCTAssertEqual(TextResolver.word(in: text, atUTF16Offset: 4), "Don't")
        XCTAssertEqual(TextResolver.word(in: text, atUTF16Offset: 11), "re-open")
        // The joiner itself is punctuation, not a letter.
        XCTAssertNil(TextResolver.word(in: text, atUTF16Offset: 3))
    }

    func testCurlyApostropheAndAccentedLetters() {
        let text = "It’s a café"
        XCTAssertEqual(TextResolver.word(in: text, atUTF16Offset: 1), "It’s")
        XCTAssertEqual(TextResolver.word(in: text, atUTF16Offset: 9), "café")
    }

    func testWordRangeMatchesResolvedWord() {
        let text = "🙂 Open Settings."
        let range = TextResolver.wordRange(in: text, atUTF16Offset: 10)
        XCTAssertEqual(range, NSRange(location: 8, length: 8))
    }

    func testEmojiOffsetIsNotAWord() {
        XCTAssertNil(TextResolver.word(in: "🙂 Open", atUTF16Offset: 0))
    }
}
