import XCTest
@testable import HoverTranslate

/// The bundled wordbook: parsing, lookup and the two caps the card shows.
///
/// The tab-separated text is the format the app ships, so these tests drive the
/// real parser instead of a stand-in. All sample text here is synthetic.
final class WordBookTests: XCTestCase {
    private func book(entries: String, lemmas: String = "") -> WordBook {
        WordBook(entries: entries, lemmas: lemmas)
    }

    // MARK: - Part of speech and the two caps

    func testPartsOfSpeechAreListedInSourceOrder() {
        let book = book(entries: "run\tn.\t跑;赛跑;奔跑\tvi.\t跑;奔跑;跑步\tvt.\t使跑;参赛;追究\ta.\t熔化的\t[计]\t运行\n")

        let entry = book.entry(for: "run")

        XCTAssertEqual(entry?.senses.map(\.partOfSpeech), ["n.", "vi.", "vt."],
                       "groups keep the order the wordbook lists them in")
        XCTAssertEqual(entry?.senses.map { $0.glosses.count }, [1, 1, 1],
                       "five parts of speech still list three of them, one meaning each")
        XCTAssertEqual(entry?.truncated, true, "the card has to be able to say that more exists")
    }

    func testAWordWithThreePartsOfSpeechShowsOneGlossEach() {
        let book = book(entries: "open\tn.\t公开;户外\ta.\t开着的;开放的\tvt.\t打开;公开\n")

        let entry = book.entry(for: "open")

        XCTAssertEqual(entry?.senses.map(\.partOfSpeech), ["n.", "a.", "vt."])
        XCTAssertEqual(entry?.senses.map { $0.glosses.count }, [1, 1, 1])
    }

    func testAShortEntryIsNotMarkedTruncated() {
        let short = book(entries: "perceive\tvt.\t感觉;认知\n").entry(for: "perceive")

        XCTAssertEqual(short?.senses.map(\.glosses), [["感觉", "认知"]])
        XCTAssertEqual(short?.truncated, false)

        let two = book(entries: "charge\tn.\t指控;费用;冲锋\tvt.\t控诉;加罪于;使充满\n")
            .entry(for: "charge")
        XCTAssertEqual(two?.senses.map { $0.glosses.count }, [2, 1],
                       "with two parts of speech the earlier one takes the spare meaning")
    }

    func testARegisterLabelIsItsOwnGroup() {
        let book = book(entries: "execute\tvt.\t执行;实行\t[计]\t执行\n")

        let entry = book.entry(for: "execute")

        XCTAssertEqual(entry?.senses.map(\.partOfSpeech), ["vt.", "[计]"],
                       "a register label such as [计] is shown as the meaning it belongs to")
    }

    func testALineWithoutPartOfSpeechKeepsAnEmptyLabel() {
        let book = book(entries: "foo\t\t说明\n")

        let entry = book.entry(for: "foo")

        XCTAssertEqual(entry?.senses, [WordSense(partOfSpeech: "", glosses: ["说明"])])
    }

    // MARK: - Lookup

    func testLookupIgnoresCase() {
        let book = book(entries: "cancel\tvt.\t取消\n")

        XCTAssertEqual(book.entry(for: "Cancel")?.senses.first?.glosses, ["取消"])
        XCTAssertEqual(book.entry(for: "CANCEL")?.senses.first?.glosses, ["取消"])
    }

    func testAnInflectedFormResolvesToItsLemma() {
        let book = book(entries: "charge\tvt.\t收费;充电\n", lemmas: "charges\tcharge\n")

        XCTAssertEqual(book.entry(for: "charges")?.word, "charge")
        XCTAssertEqual(book.entry(for: "charges")?.senses.first?.glosses, ["收费", "充电"])
    }

    func testAPossessiveResolvesToTheBaseWord() {
        let book = book(entries: "user\tn.\t用户\n")

        XCTAssertEqual(book.entry(for: "user's")?.word, "user")
        XCTAssertEqual(book.entry(for: "user’s")?.word, "user", "a typographic apostrophe counts too")
    }

    func testAnUnknownWordHasNoEntry() {
        XCTAssertNil(book(entries: "cancel\tvt.\t取消\n").entry(for: "zzzznope"))
    }

    func testAnEmptyOrBlankWordHasNoEntry() {
        let book = book(entries: "cancel\tvt.\t取消\n")

        XCTAssertNil(book.entry(for: ""))
        XCTAssertNil(book.entry(for: "   "))
        XCTAssertNil(book.entry(for: "two words"))
    }

    // MARK: - The shipped file

    func testTheBundledWordbookAnswersForTheCommonCase() throws {
        let book = try XCTUnwrap(WordBook.bundled(), "the wordbook has to be copied into the app")

        let run = try XCTUnwrap(book.entry(for: "run"))
        XCTAssertEqual(run.senses.map(\.partOfSpeech).prefix(2), ["n.", "vi."],
                       "a word with several parts of speech lists them in order")
        XCTAssertNotNil(book.entry(for: "settings"), "a plural form still answers")
        XCTAssertNotNil(book.entry(for: "button"))
    }
}