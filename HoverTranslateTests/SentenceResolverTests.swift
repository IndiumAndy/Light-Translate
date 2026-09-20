import XCTest
@testable import HoverTranslate

/// v0.3 task 1, rewritten for the 2026-09-19 cross-line design.
///
/// Two phases are covered in one file because they are one decision: the
/// normalizer folds single line breaks and keeps every offset mapped back, and
/// the resolver decides how much of the sentence is actually proven. Every case
/// is synthetic text; no user content is used.
final class SentenceResolverTests: XCTestCase {
    private func offset(of needle: String, in text: String) -> Int {
        (text as NSString).range(of: needle).location
    }

    /// A whole element, read from its first character to its last.
    private func resolve(_ text: String,
                         at needle: String,
                         windowStart: Int = 0,
                         elementEnd: Int? = nil) -> SentenceResolver.Resolution? {
        SentenceResolver.resolve(in: SentenceWindow(text: text,
                                                    windowStart: windowStart,
                                                    elementEnd: elementEnd ?? (text as NSString).length),
                                 atUTF16Offset: offset(of: needle, in: text))
    }

    /// Text assembled from the lines of one screenshot: its own edges prove
    /// nothing about the document behind it.
    private func resolveFragment(_ text: String, at needle: String) -> SentenceResolver.Resolution? {
        SentenceResolver.resolve(in: .fragment(text), atUTF16Offset: offset(of: needle, in: text))
    }

    // MARK: - Only the sentence that contains the hit

    func testOnlySentenceContainingTargetIsReturned() {
        let text = "Open Settings. You can change the language here."
        let resolution = resolve(text, at: "language")
        XCTAssertEqual(resolution?.text, "You can change the language here.")
        XCTAssertEqual(resolution?.completeness, .complete)
        XCTAssertEqual(resolution?.boundary, .complete)
    }

    func testInvalidIndexIsRejected() {
        let window = SentenceWindow(text: "Open Settings.", windowStart: 0, elementEnd: 14)
        XCTAssertNil(SentenceResolver.resolve(in: window, atUTF16Offset: 100))
        XCTAssertNil(SentenceResolver.resolve(in: window, atUTF16Offset: -1))
    }

    /// The space between two sentences belongs to neither.
    func testWhitespaceBetweenSentencesIsNotASentence() {
        let text = "Open Settings. You can change the language here."
        XCTAssertNil(resolve(text, at: " You"))
    }

    func testAbbreviationDoesNotSplitTheSentence() {
        let text = "Dr. Smith went home. He slept well."
        XCTAssertEqual(resolve(text, at: "Smith")?.text, "Dr. Smith went home.")
    }

    func testDecimalDoesNotSplitTheSentence() {
        let text = "The value is 3.14 exactly. Done."
        XCTAssertEqual(resolve(text, at: "exactly")?.text, "The value is 3.14 exactly.")
    }

    /// A domain's dot has no space after it, so it is not a sentence end.
    func testDomainDotsDoNotSplitTheSentence() {
        let text = "See example.com for details. Then leave."
        XCTAssertEqual(resolve(text, at: "details")?.text, "See example.com for details.")
    }

    /// A surrogate pair shifts every UTF-16 offset after it, so the offset the
    /// Accessibility layer reports is only usable on the UTF-16 view.
    func testEmojiBeforeTheHitKeepsOffsetsCorrect() {
        let text = "Open 🙂 Settings. Next one."
        XCTAssertEqual((text as NSString).range(of: "Settings").location, 8)
        XCTAssertEqual(resolve(text, at: "Settings")?.text, "Open 🙂 Settings.")
    }

    func testChineseTerminatorEndsTheSentence() {
        let text = "这是第一句。这是第二句。"
        XCTAssertEqual(resolve(text, at: "第二")?.text, "这是第二句。")
    }

    func testAClosingQuoteAfterTheTerminatorIsPartOfTheSentence() {
        let text = "He said \"stop.\" Then he left."
        let resolution = resolve(text, at: "stop")
        XCTAssertEqual(resolution?.text, "He said \"stop.\"")
        XCTAssertEqual(resolution?.completeness, .complete)
    }

    // MARK: - A single line break is typography

    func testASentenceWrappedOverTwoLinesIsReadWhole() {
        let text = "First one is here. This sentence wraps\nonto another line. Third one is here."
        let resolution = resolve(text, at: "wraps")
        XCTAssertEqual(resolution?.text, "This sentence wraps onto another line.")
        XCTAssertEqual(resolution?.completeness, .complete,
                       "the wrap is typography, and both terminators are inside the window")
    }

    /// The original range still points at the un-normalized text, folded run
    /// included: the card anchors on it and the bounds query needs it.
    func testTheOriginalRangeCoversTheFoldedRun() {
        let text = "This sentence wraps \n onto another line."
        let resolution = resolve(text, at: "onto")
        XCTAssertEqual(resolution?.text, "This sentence wraps onto another line.")
        XCTAssertEqual(resolution?.originalRange, NSRange(location: 0, length: (text as NSString).length))
        XCTAssertEqual((text as NSString).substring(with: resolution!.originalRange), text)
    }

    func testABlankLineIsNeverCrossed() {
        let text = "First paragraph is here.\n\nSecond one starts here."
        XCTAssertEqual(resolve(text, at: "Second")?.text, "Second one starts here.")
        XCTAssertEqual(resolve(text, at: "Second")?.completeness, .complete,
                       "a paragraph boundary proves where the sentence starts")
        XCTAssertEqual(resolve(text, at: "First")?.text, "First paragraph is here.")
    }

    /// Folded line breaks are not sentence terminators: a list without any
    /// punctuation is a fragment, not a wrapped sentence.
    func testAListWithoutTerminatorsStaysPartial() {
        let text = "First item\nSecond item\nThird item"
        let resolution = resolve(text, at: "Second")
        XCTAssertEqual(resolution?.completeness, .partial)
        XCTAssertTrue(resolution?.text.contains("Second item") == true, "text: \(resolution?.text ?? "-")")
    }

    // MARK: - Proven boundaries only

    func testASentenceTouchingAClippedWindowStartIsPartial() {
        let text = "change the language here."
        let resolution = resolve(text, at: "language", windowStart: 900, elementEnd: 3_000)
        XCTAssertEqual(resolution?.text, "change the language here.")
        XCTAssertEqual(resolution?.completeness, .partial)
        XCTAssertEqual(resolution?.boundary, .clippedStart, "the sentence may begin before the bounded window")
    }

    func testASentenceRunningPastAClippedWindowEndIsPartial() {
        let text = "You can change the language"
        let offset = offset(of: "language", in: text)
        XCTAssertEqual(SentenceResolver.resolve(in: SentenceWindow(text: text, windowStart: 0, elementEnd: 4_000),
                                                atUTF16Offset: offset)?.boundary, .clippedEnd)
        XCTAssertEqual(SentenceResolver.resolve(in: SentenceWindow(text: text, windowStart: 0, elementEnd: nil),
                                                atUTF16Offset: offset)?.boundary, .clippedEnd,
                       "an unknown element length can never confirm the end")
    }

    /// A fragment with a proven start but no terminator is still a fragment,
    /// even when it is the element's last line.
    func testAFragmentWithoutATerminatorIsPartial() {
        let text = "Open Settings"
        let resolution = resolve(text, at: "Settings")
        XCTAssertEqual(resolution?.completeness, .partial)
        XCTAssertEqual(resolution?.boundary, .missingTerminator)
    }

    // MARK: - OCR text proves only what is inside the capture

    func testASingleRecognizedLineIsNeverAWholeSentence() {
        XCTAssertEqual(resolveFragment("Open Settings", at: "Settings")?.boundary, .clippedStart)
    }

    func testAFragmentWithATerminatorBeforeAndAfterTheSentenceIsComplete() {
        let resolution = resolveFragment("First one. Open Settings. Next one.", at: "Settings")
        XCTAssertEqual(resolution?.text, "Open Settings.")
        XCTAssertEqual(resolution?.completeness, .complete)
    }

    func testAFragmentWithoutATerminatorAtTheEndStaysPartial() {
        let resolution = resolveFragment("First one. Open Settings", at: "Settings")
        XCTAssertEqual(resolution?.text, "Open Settings")
        XCTAssertEqual(resolution?.completeness, .partial)
        XCTAssertEqual(resolution?.boundary, .clippedEnd)
    }

    // MARK: - Normalizer

    func testASingleLineBreakAndTheSpaceAroundItBecomeOneSpace() {
        XCTAssertEqual(SentenceContextNormalizer.normalize("This sentence wraps \n onto another line.").text,
                       "This sentence wraps onto another line.")
        XCTAssertEqual(SentenceContextNormalizer.normalize("First line\nsecond line").text,
                       "First line second line")
    }

    func testABlankLineSurvivesNormalization() {
        XCTAssertEqual(SentenceContextNormalizer.normalize("First paragraph.\n\nSecond paragraph.").text,
                       "First paragraph.\n\nSecond paragraph.")
    }

    func testTextWithoutALineBreakKeepsItsOffsets() {
        let text = "Open Settings. You can change the language here."
        let normalized = SentenceContextNormalizer.normalize(text)
        XCTAssertEqual(normalized.text, text)
        XCTAssertEqual(normalized.originalRange(forNormalized: NSRange(location: 5, length: 8)),
                       NSRange(location: 5, length: 8))
        XCTAssertEqual(normalized.normalizedOffset(forOriginal: 5), 5)
    }

    func testAFoldedBreakMapsBothWays() {
        let text = "This sentence wraps \n onto another line."
        let normalized = SentenceContextNormalizer.normalize(text)
        XCTAssertEqual(normalized.text, "This sentence wraps onto another line.")

        let original = offset(of: "onto", in: text)
        let mapped = normalized.normalizedOffset(forOriginal: original)
        XCTAssertEqual(mapped, offset(of: "onto", in: normalized.text))
        XCTAssertEqual(normalized.originalRange(forNormalized: NSRange(location: mapped!, length: 4)),
                       NSRange(location: original, length: 4))
        XCTAssertEqual(normalized.originalRange(forNormalized: NSRange(location: 0, length: mapped!)),
                       NSRange(location: 0, length: original),
                       "the text before the fold covers the whole run it replaced")
    }

    func testAnOffsetInsideTheFoldedBreakMapsToTheSpaceThatReplacedIt() {
        let text = "wraps \n onto"
        let normalized = SentenceContextNormalizer.normalize(text)
        XCTAssertEqual(normalized.text, "wraps onto")
        XCTAssertEqual(normalized.normalizedOffset(forOriginal: offset(of: "\n", in: text)),
                       offset(of: " ", in: normalized.text))
    }

    func testOtherUnicodeLineBreaksFoldLikeANewline() {
        XCTAssertEqual(SentenceContextNormalizer.normalize("one\u{2028}two").text, "one two")
        XCTAssertEqual(SentenceContextNormalizer.normalize("one\u{85}two").text, "one two")
        XCTAssertEqual(SentenceContextNormalizer.normalize("one\r\ntwo").text, "one two",
                       "CRLF is one line ending, not a paragraph break")
        XCTAssertEqual(SentenceContextNormalizer.normalize("one\r\n\r\ntwo").text, "one\r\n\r\ntwo")
    }

    func testSurrogatePairsKeepTheirOffsets() {
        let text = "Open 🙂\nSettings."
        let normalized = SentenceContextNormalizer.normalize(text)
        XCTAssertEqual(normalized.text, "Open 🙂 Settings.")
        XCTAssertEqual(normalized.normalizedOffset(forOriginal: offset(of: "Settings", in: text)),
                       offset(of: "Settings", in: normalized.text))
    }

    func testAnOffsetOutsideTheTextHasNoMapping() {
        let normalized = SentenceContextNormalizer.normalize("Open Settings.")
        XCTAssertNil(normalized.normalizedOffset(forOriginal: 500))
        XCTAssertNil(normalized.originalRange(forNormalized: NSRange(location: 90, length: 2)))
        XCTAssertNil(normalized.originalRange(forNormalized: NSRange(location: 0, length: 0)))
    }
}
