import XCTest
@testable import HoverTranslate

/// v0.3 task 2: which recognized word, if any, is under the pointer.
final class OCRHitTesterTests: XCTestCase {
    private func word(_ text: String, _ rect: CGRect, _ confidence: Float = 0.99) -> OCRWord {
        OCRWord(text: text, rect: rect, confidence: confidence)
    }

    func testWhitespaceDoesNotPickNearestWord() {
        let words = [OCRWord(text: "Open",
                             rect: CGRect(x: 0, y: 0, width: 40, height: 20),
                             confidence: 0.99)]
        XCTAssertNil(OCRHitTester.pick(point: CGPoint(x: 90, y: 10), words: words))
        XCTAssertEqual(OCRHitTester.pick(point: CGPoint(x: 20, y: 10), words: words)?.text, "Open")
    }

    func testHitToleranceIsTwoScreenPoints() {
        let words = [word("Open", CGRect(x: 0, y: 0, width: 40, height: 20))]
        XCTAssertEqual(OCRHitTester.pick(point: CGPoint(x: -1.5, y: 10), words: words)?.text, "Open")
        XCTAssertNil(OCRHitTester.pick(point: CGPoint(x: -2.5, y: 10), words: words))
    }

    func testLowConfidenceIsNeverAnAutomaticAnswer() {
        let words = [word("0pen", CGRect(x: 0, y: 0, width: 40, height: 20), 0.64)]
        XCTAssertNil(OCRHitTester.pick(point: CGPoint(x: 20, y: 10), words: words))
        let confident = [word("Open", CGRect(x: 0, y: 0, width: 40, height: 20), 0.65)]
        XCTAssertEqual(OCRHitTester.pick(point: CGPoint(x: 20, y: 10), words: confident)?.text, "Open")
    }

    func testTheWordContainingThePointWins() {
        let words = [word("Open", CGRect(x: 0, y: 0, width: 40, height: 20)),
                     word("Settings", CGRect(x: 60, y: 0, width: 70, height: 20))]
        XCTAssertEqual(OCRHitTester.pick(point: CGPoint(x: 80, y: 10), words: words)?.text, "Settings")
        XCTAssertNil(OCRHitTester.pick(point: CGPoint(x: 50, y: 10), words: words))
    }

    func testLineRunJoinsWordsOfTheSameLineInReadingOrder() {
        let words = [word("language", CGRect(x: 86, y: 0, width: 70, height: 20)),
                     word("You", CGRect(x: 0, y: 0, width: 30, height: 20)),
                     word("change", CGRect(x: 36, y: 0, width: 44, height: 20)),
                     word("here.", CGRect(x: 162, y: 0, width: 40, height: 20))]
        let hit = words[0]
        XCTAssertEqual(OCRHitTester.lineRun(containing: hit, words: words).map(\.text),
                       ["You", "change", "language", "here."])
    }

    func testLineRunStopsAtAColumnGap() {
        let left = [word("Left", CGRect(x: 0, y: 0, width: 40, height: 20)),
                    word("column", CGRect(x: 44, y: 0, width: 60, height: 20))]
        let right = [word("Right", CGRect(x: 200, y: 0, width: 50, height: 20)),
                     word("column", CGRect(x: 254, y: 0, width: 60, height: 20))]
        XCTAssertEqual(OCRHitTester.lineRun(containing: left[0], words: left + right).map(\.text),
                       ["Left", "column"])
        XCTAssertEqual(OCRHitTester.lineRun(containing: right[0], words: left + right).map(\.text),
                       ["Right", "column"])
    }

    func testLineRunIgnoresOtherLinesAndLowConfidenceWords() {
        let words = [word("Open", CGRect(x: 0, y: 0, width: 40, height: 20)),
                     word("Settings", CGRect(x: 44, y: 0, width: 60, height: 20), 0.4),
                     word("Below", CGRect(x: 0, y: 30, width: 50, height: 20))]
        XCTAssertEqual(OCRHitTester.lineRun(containing: words[0], words: words).map(\.text), ["Open"])
    }

    // MARK: - Multi-line context (2026-09-19 cross-line sentence design)

    /// Vision reports one observation per visual line; the fake does the same.
    private func line(_ words: [OCRWord]) -> OCRLine {
        OCRLine(text: words.map(\.text).joined(separator: " "), words: words)
    }

    func testTheHitLineIsAlwaysItsOwnContext() {
        let words = [word("Open", CGRect(x: 0, y: 0, width: 40, height: 20))]
        XCTAssertEqual(OCRHitTester.contextLines(containing: words[0], lines: [line(words)]).map { $0.map(\.text) },
                       [["Open"]])
    }

    /// AppKit y grows upward, so the upper line carries the larger y.
    private func wrappedParagraph() -> [OCRLine] {
        let upper = [word("This", CGRect(x: 0, y: 26, width: 40, height: 20)),
                     word("sentence", CGRect(x: 44, y: 26, width: 80, height: 20)),
                     word("wraps", CGRect(x: 128, y: 26, width: 50, height: 20))]
        let lower = [word("onto", CGRect(x: 0, y: 0, width: 40, height: 20)),
                     word("another", CGRect(x: 44, y: 0, width: 70, height: 20)),
                     word("line.", CGRect(x: 118, y: 0, width: 40, height: 20))]
        return [line(upper), line(lower)]
    }

    func testALineBelowTheHitJoinsTheContext() {
        let lines = wrappedParagraph()
        let hit = lines[0].words[2]
        XCTAssertEqual(OCRHitTester.contextLines(containing: hit, lines: lines).map { $0.map(\.text) },
                       [["This", "sentence", "wraps"], ["onto", "another", "line."]])
    }

    func testTheContextAlsoGrowsUpwardFromTheHit() {
        let lines = wrappedParagraph()
        let hit = lines[1].words[0]
        XCTAssertEqual(OCRHitTester.contextLines(containing: hit, lines: lines).map { $0.map(\.text) },
                       [["This", "sentence", "wraps"], ["onto", "another", "line."]])
    }

    /// A line that shares its row with another column is a column, not half of
    /// a wrapped paragraph, so nothing is joined to it.
    func testTwoColumnsAreNeverJoined() {
        let leftTop = [word("Left", CGRect(x: 0, y: 26, width: 40, height: 20)),
                       word("column", CGRect(x: 44, y: 26, width: 60, height: 20))]
        let rightTop = [word("Right", CGRect(x: 200, y: 26, width: 50, height: 20)),
                        word("column", CGRect(x: 254, y: 26, width: 60, height: 20))]
        let leftBottom = [word("More", CGRect(x: 0, y: 0, width: 44, height: 20)),
                          word("left", CGRect(x: 48, y: 0, width: 30, height: 20))]
        let rightBottom = [word("More", CGRect(x: 200, y: 0, width: 44, height: 20)),
                           word("right", CGRect(x: 248, y: 0, width: 34, height: 20))]
        let lines = [line(leftTop), line(rightTop), line(leftBottom), line(rightBottom)]
        XCTAssertEqual(OCRHitTester.contextLines(containing: leftTop[0], lines: lines).map { $0.map(\.text) },
                       [["Left", "column"]])
    }

    /// In a table every cell is its own observation, so a cell never joins the
    /// cell above or below it.
    func testATableIsNeverJoinedAcrossCells() {
        let lines = [line([word("Name", CGRect(x: 0, y: 26, width: 60, height: 20))]),
                     line([word("Age", CGRect(x: 300, y: 26, width: 40, height: 20))]),
                     line([word("Alice", CGRect(x: 0, y: 0, width: 70, height: 20))]),
                     line([word("30", CGRect(x: 300, y: 0, width: 24, height: 20))])]
        XCTAssertEqual(OCRHitTester.contextLines(containing: lines[2].words[0], lines: lines).map { $0.map(\.text) },
                       [["Alice"]])
    }

    func testALargeVerticalGapStopsTheContext() {
        let lines = [line([word("Heading", CGRect(x: 0, y: 200, width: 90, height: 20))]),
                     line([word("Body", CGRect(x: 0, y: 0, width: 40, height: 20))])]
        XCTAssertEqual(OCRHitTester.contextLines(containing: lines[1].words[0], lines: lines).map { $0.map(\.text) },
                       [["Body"]])
    }

    func testASentenceIsNeverJoinedToFarAwayText() {
        let lines = [line([word("Far", CGRect(x: 400, y: 26, width: 40, height: 20))]),
                     line([word("Near", CGRect(x: 0, y: 0, width: 44, height: 20))])]
        XCTAssertEqual(OCRHitTester.contextLines(containing: lines[1].words[0], lines: lines).map { $0.map(\.text) },
                       [["Near"]],
                       "a horizontal range that does not overlap is a different block")
    }

    func testTheContextIsBoundedByItsLineLimit() {
        let lines = (0..<8).map { index in
            line([word("Line\(index)", CGRect(x: 0, y: CGFloat(index) * 26, width: 60, height: 20))])
        }
        let context = OCRHitTester.contextLines(containing: lines[0].words[0], lines: lines)
        XCTAssertEqual(context.count, OCRHitTester.maximumContextLines)
    }
}
