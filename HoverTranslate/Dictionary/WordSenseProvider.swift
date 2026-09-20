import Foundation
import os

/// The offline meanings for one word.
///
/// Deliberately separate from `TranslationService`: the wordbook is a local file
/// that needs no key, no permission and no network, and it is only ever asked
/// about a word the app has already read. It is not a third translation engine.
protocol WordSenseProviding: Sendable {
    /// The meanings for one word, or nil when the wordbook has none.
    func entry(for word: String) async -> WordEntry?
}

/// The wordbook that ships inside the app, read once on first use.
///
/// Loading parses about 2.6 MB of text, so it happens on the actor's executor
/// instead of the main actor. A missing resource is not an error: the provider
/// then answers nil and the card simply shows no dictionary section.
actor BundledWordBookProvider: WordSenseProviding {
    /// Content-free diagnostics: whether the shipped file was found at all, so
    /// "no dictionary section" can be told apart from "the resource is missing".
    private let log = Logger(subsystem: "com.atat.HoverTranslate", category: "dictionary")
    private let entriesURL: URL?
    private let lemmasURL: URL?
    private var book: WordBook?
    private var didReportLoad = false

    init(bundle: Bundle = .main) {
        entriesURL = bundle.url(forResource: "WordBook", withExtension: "tsv")
        lemmasURL = bundle.url(forResource: "WordBookLemmas", withExtension: "tsv")
    }

    func entry(for word: String) async -> WordEntry? {
        if book == nil, let entriesURL, let lemmasURL {
            book = WordBook(contentsOf: entriesURL, lemmasAt: lemmasURL)
        }
        if !didReportLoad {
            didReportLoad = true
            log.debug("wordbook loaded=\(self.book != nil, privacy: .public)")
        }
        return book?.entry(for: word)
    }
}
