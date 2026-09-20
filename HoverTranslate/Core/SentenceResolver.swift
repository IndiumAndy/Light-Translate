import Foundation
import NaturalLanguage

/// The bounded text a sentence is resolved in, plus what is known about its two
/// edges.
struct SentenceWindow: Equatable, Sendable {
    let text: String
    /// The text begins at the source element's own first character, so a
    /// sentence starting at offset 0 has a proven left boundary.
    let startsAtElementStart: Bool
    /// The text ends at the element's own last character.
    let endsAtElementEnd: Bool

    /// A bounded read of one element: `windowStart` is the window's offset
    /// inside the element, `elementEnd` the element's total length when it
    /// reported one.
    init(text: String, windowStart: Int, elementEnd: Int?) {
        let length = (text as NSString).length
        self.init(text: text,
                  startsAtElementStart: windowStart == 0,
                  endsAtElementEnd: elementEnd.map { windowStart + length >= $0 } ?? false)
    }

    /// A local fragment whose edges prove nothing: the lines recognized in one
    /// screenshot are not the whole document behind them.
    static func fragment(_ text: String) -> SentenceWindow {
        SentenceWindow(text: text, startsAtElementStart: false, endsAtElementEnd: false)
    }

    private init(text: String, startsAtElementStart: Bool, endsAtElementEnd: Bool) {
        self.text = text
        self.startsAtElementStart = startsAtElementStart
        self.endsAtElementEnd = endsAtElementEnd
    }
}

/// v0.3, extended 2026-09-19: finds the sentence that contains a UTF-16 offset.
///
/// Resolution has two phases. `SentenceContextNormalizer` folds the line breaks
/// of the bounded read first, so a sentence wrapped over two lines is read whole
/// and a paragraph break survives as the boundary it is. The system sentence
/// tokenizer then finds the candidate on the normalized text — it keeps
/// abbreviations ("Dr."), decimals ("3.14") and quoted terminators together —
/// and the boundary rules below decide how much of it is actually proven:
///
/// - a proven left edge is the element's own start, a sentence terminator (with
///   its closing quotes) or a paragraph break before the sentence;
/// - a proven right edge is a sentence terminator at the end of the sentence;
/// - everything else is `.partial`, which the card shows as such instead of
///   passing a fragment off as the whole sentence.
///
/// The resolver only ever sees a bounded window of the element's text, so the
/// hit offset and every range here are UTF-16 units relative to that window.
enum SentenceResolver {
    /// The design's initial bounded read: at most 2000 UTF-16 units around the
    /// hit. A window this size cannot hold a paragraph, but it does hold
    /// ordinary sentences, and clipping is detectable at both edges.
    static let maximumWindowLength = 2_000

    /// One resolved sentence.
    struct Resolution: Equatable, Sendable {
        /// The sentence's range in the original — un-normalized — text.
        let originalRange: NSRange
        /// The sentence as it is shown and translated: single line, with folded
        /// line breaks.
        let text: String
        let completeness: ExtractionCompleteness
        /// Why the sentence is or is not proven whole. Contains no user text,
        /// which is why it is also the log category.
        let boundary: Boundary

        var isComplete: Bool { completeness == .complete }
    }

    /// The outcome of the boundary check, as a content-free category.
    enum Boundary: String, Equatable, Sendable {
        case complete
        /// The sentence starts at the window's first character, but the window
        /// is not the start of the element.
        case clippedStart
        /// The sentence reaches the window's last character with no terminator,
        /// and the window is not the end of the element.
        case clippedEnd
        /// A proven left edge, but the sentence carries no terminator.
        case missingTerminator
        /// The text before the sentence proves no boundary at all.
        case missingBoundary
    }

    /// The sentence containing `offset`, or nil when that offset is not inside
    /// one (an invalid index, or whitespace between two sentences).
    static func resolve(in window: SentenceWindow, atUTF16Offset offset: Int) -> Resolution? {
        let context = SentenceContextNormalizer.normalize(window.text)
        guard let normalizedOffset = context.normalizedOffset(forOriginal: offset),
              let range = sentenceRange(in: context.text, atUTF16Offset: normalizedOffset),
              let originalRange = context.originalRange(forNormalized: range) else { return nil }
        let sentence = (context.text as NSString).substring(with: range)
        let boundary = boundary(range: range,
                                sentence: sentence,
                                normalized: context.text,
                                window: window)
        return Resolution(originalRange: originalRange,
                          text: sentence,
                          completeness: boundary == .complete ? .complete : .partial,
                          boundary: boundary)
    }

    // MARK: - Private

    /// The tokenizer's sentence, trimmed of surrounding whitespace, with the
    /// offset proven to be inside it.
    private static func sentenceRange(in text: String, atUTF16Offset offset: Int) -> NSRange? {
        let string = text as NSString
        guard offset >= 0, offset < string.length else { return nil }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var found: NSRange?
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let candidate = NSRange(range, in: text)
            if candidate.location <= offset, offset < candidate.location + candidate.length {
                found = candidate
                return false
            }
            return true
        }
        guard let token = found else { return nil }

        let trimmed = trimmingWhitespace(token, in: string)
        guard trimmed.length > 0,
              offset >= trimmed.location,
              offset < trimmed.location + trimmed.length else { return nil }
        return trimmed
    }

    private static func boundary(range: NSRange,
                                 sentence: String,
                                 normalized: String,
                                 window: SentenceWindow) -> Boundary {
        if range.location == 0 {
            guard window.startsAtElementStart else { return .clippedStart }
        } else if !endsABoundary(before: range.location, in: normalized) {
            return .missingBoundary
        }
        guard endsWithTerminator(sentence) else {
            let length = (normalized as NSString).length
            if range.location + range.length >= length, !window.endsAtElementEnd { return .clippedEnd }
            return .missingTerminator
        }
        return .complete
    }

    /// Whether the text just before `location` proves where a sentence starts:
    /// a terminator with its closing quotes, or a paragraph break. A line break
    /// that survived normalization means there were two, and a blank line is a
    /// boundary this design never crosses.
    private static func endsABoundary(before location: Int, in text: String) -> Bool {
        let string = text as NSString
        var index = location - 1
        while index >= 0, isWhitespace(string.character(at: index)) {
            if isLineBreak(string.character(at: index)) { return true }
            index -= 1
        }
        while index >= 0, isCloser(string.character(at: index)) { index -= 1 }
        return index >= 0 && isTerminator(string.character(at: index))
    }

    private static func endsWithTerminator(_ sentence: String) -> Bool {
        let string = sentence as NSString
        var index = string.length - 1
        while index >= 0, isCloser(string.character(at: index)) { index -= 1 }
        return index >= 0 && isTerminator(string.character(at: index))
    }

    private static func trimmingWhitespace(_ range: NSRange, in text: NSString) -> NSRange {
        var start = range.location
        var end = range.location + range.length
        while start < end, isWhitespace(text.character(at: start)) { start += 1 }
        while end > start, isWhitespace(text.character(at: end - 1)) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }

    private static func isWhitespace(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    private static func isLineBreak(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.newlines.contains(scalar)
    }

    /// The terminators the design accepts. A dot inside a word ("example.com",
    /// "3.14") is never reached here: the tokenizer does not split there, and a
    /// terminator only counts at the end of a sentence.
    private static func isTerminator(_ unit: unichar) -> Bool {
        ".!?…。！？".utf16.contains(unit)
    }

    private static func isCloser(_ unit: unichar) -> Bool {
        "\"'”’)]»）】」".utf16.contains(unit)
    }
}
