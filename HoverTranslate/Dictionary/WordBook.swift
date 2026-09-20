import Foundation

/// One part of speech and the meanings the wordbook lists under it.
struct WordSense: Equatable, Sendable {
    /// "n." / "vt." / "[计]" — empty when the source gave no part of speech.
    let partOfSpeech: String
    let glosses: [String]
}

/// What the card shows for one word: its meanings, already capped.
struct WordEntry: Equatable, Sendable {
    /// The wordbook's own spelling of the word that answered.
    let word: String
    let senses: [WordSense]
    /// True when the wordbook holds more meanings than the card shows.
    let truncated: Bool
}

/// The bundled English-to-Chinese wordbook: the only offline source of parts of
/// speech and of several meanings per word.
///
/// Provenance and licence: `docs/THIRD_PARTY_NOTICES.md`. The shipped file holds
/// one word per line, tab separated, with (part of speech, meanings) pairs:
///
///     word <tab> pos <tab> gloss;gloss <tab> pos <tab> gloss ...
///
/// and a second file maps an inflected form to its base word. Both are plain
/// text so a test can drive the real parser with a few synthetic lines.
struct WordBook: Sendable {
    /// A part of speech shows at most this many meanings.
    static let glossesPerPartOfSpeech = 2
    /// The card shows at most this many meanings in total, so a word with three
    /// parts of speech lists all three with one meaning each instead of spending
    /// the whole budget on the first one.
    static let totalGlosses = 3

    private struct Record: Sendable {
        let word: String
        let senses: [WordSense]
    }

    private let records: [String: Record]
    private let lemmas: [String: String]

    init(entries: String, lemmas: String = "") {
        self.records = Self.parse(entries: entries)
        self.lemmas = Self.parseLemmas(lemmas)
    }

    /// Reads the two shipped files. nil when either cannot be read, in which case
    /// the card simply shows no dictionary section.
    init?(contentsOf entries: URL, lemmasAt lemmas: URL) {
        guard let entryText = try? String(contentsOf: entries, encoding: .utf8),
              let lemmaText = try? String(contentsOf: lemmas, encoding: .utf8) else { return nil }
        self.init(entries: entryText, lemmas: lemmaText)
    }

    /// The wordbook that ships inside the app.
    static func bundled(in bundle: Bundle = .main) -> WordBook? {
        guard let entries = bundle.url(forResource: "WordBook", withExtension: "tsv"),
              let lemmas = bundle.url(forResource: "WordBookLemmas", withExtension: "tsv") else { return nil }
        return WordBook(contentsOf: entries, lemmasAt: lemmas)
    }

    /// The meanings for one word, or nil when the wordbook has none.
    ///
    /// An exact word wins over an inflected form, so "settings" answers with its
    /// own entry instead of with "setting".
    func entry(for word: String) -> WordEntry? {
        guard let key = Self.key(for: word), let record = record(for: key) else { return nil }
        let (senses, truncated) = Self.capped(record.senses)
        return WordEntry(word: record.word, senses: senses, truncated: truncated)
    }

    // MARK: - Lookup

    private func record(for key: String) -> Record? {
        if let record = records[key] { return record }
        guard let lemma = lemmas[key] else { return nil }
        return records[lemma]
    }

    /// The dictionary key for a word read from screen: lower case, without a
    /// possessive ending. A phrase, a blank, or anything with a space in it is
    /// not a word this book can answer for.
    private static func key(for word: String) -> String? {
        var text = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasSuffix("'s") || text.hasSuffix("’s") {
            text = String(text.dropLast(2))
        }
        guard !text.isEmpty, !text.contains(where: { $0.isWhitespace }) else { return nil }
        return text
    }

    // MARK: - Caps

    /// Shares the meaning budget between the parts of speech that will be shown:
    /// every one of them gets at least one meaning, and the earlier ones take
    /// what is left over.
    private static func capped(_ senses: [WordSense]) -> ([WordSense], Bool) {
        let shown = min(senses.count, totalGlosses)
        guard shown > 0 else { return ([], false) }
        let base = totalGlosses / shown
        var spare = totalGlosses - base * shown
        var result: [WordSense] = []
        var dropped = false
        for (index, sense) in senses.enumerated() {
            guard index < shown else {
                dropped = true
                break
            }
            var budget = base
            if spare > 0 {
                budget += 1
                spare -= 1
            }
            let take = min(budget, glossesPerPartOfSpeech, sense.glosses.count)
            if take < sense.glosses.count { dropped = true }
            result.append(WordSense(partOfSpeech: sense.partOfSpeech,
                                    glosses: Array(sense.glosses.prefix(take))))
        }
        return (result, dropped)
    }

    // MARK: - Parsing

    private static func parse(entries: String) -> [String: Record] {
        var records: [String: Record] = [:]
        entries.enumerateLines { line, _ in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3, !fields[0].isEmpty else { return }
            var senses: [WordSense] = []
            var index = 1
            while index + 1 < fields.count {
                let glosses = fields[index + 1]
                    .split(separator: ";")
                    .map(String.init)
                    .filter { !$0.isEmpty }
                if !glosses.isEmpty {
                    senses.append(WordSense(partOfSpeech: fields[index], glosses: glosses))
                }
                index += 2
            }
            guard !senses.isEmpty else { return }
            records[fields[0].lowercased()] = Record(word: fields[0], senses: senses)
        }
        return records
    }

    private static func parseLemmas(_ lemmas: String) -> [String: String] {
        var map: [String: String] = [:]
        lemmas.enumerateLines { line, _ in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 2, !fields[0].isEmpty, !fields[1].isEmpty else { return }
            map[fields[0].lowercased()] = fields[1].lowercased()
        }
        return map
    }
}
