import CoreGraphics
import Foundation

/// One recognized word with its real box in screen points.
struct OCRWord: Equatable, Sendable {
    let text: String
    /// AppKit screen coordinates, converted from the recognizer's normalized box.
    let rect: CGRect
    let confidence: Float
    /// The punctuation between this word and the next one inside its line.
    ///
    /// A word query stays exactly the word, while the sentence the OCR path
    /// assembles keeps its terminators — without them no boundary could ever be
    /// proven and the text sent for translation would lose its full stops.
    var trailing: String = ""
}

/// v0.3, extended 2026-09-19: which recognized word the pointer is on, and
/// which neighbouring lines could belong to the same paragraph.
///
/// There is no nearest-word fallback: whitespace has no result. A word is only
/// accepted when the pointer is inside its real box (grown by two screen points,
/// the design's initial tolerance) and the recognition was confident enough to
/// answer with, so a low-confidence guess is never handed to the model as if it
/// were the source text.
///
/// The grouping below is geometry only: it never decides where a sentence ends.
/// That is `SentenceResolver`'s job, on the text this grouping produces.
enum OCRHitTester {
    static let minimumConfidence: Float = 0.65
    static let hitTolerance: CGFloat = 2
    /// At most this many visual lines are ever joined into one context.
    static let maximumContextLines = 6

    static func pick(point: CGPoint, words: [OCRWord]) -> OCRWord? {
        words.first { word in
            word.confidence >= minimumConfidence
                && word.rect.insetBy(dx: -hitTolerance, dy: -hitTolerance).contains(point)
        }
    }

    /// The contiguous run of words on the hit's line, in reading order.
    ///
    /// Only words that overlap the hit vertically and that are close enough to
    /// be separated by a space join the run. A wide horizontal gap ends it, so
    /// two columns, or two cells of a table, are never glued into one sentence.
    static func lineRun(containing hit: OCRWord, words: [OCRWord]) -> [OCRWord] {
        let usable = words.filter { $0.confidence >= minimumConfidence && $0.rect.width > 0 && $0.rect.height > 0 }
        let line = usable
            .filter { overlapsVertically($0.rect, hit.rect) }
            .sorted { $0.rect.minX < $1.rect.minX }
        guard let index = line.firstIndex(of: hit) else { return [] }

        var lower = index
        var upper = index
        while lower > 0, joins(line[lower - 1].rect, line[lower].rect) { lower -= 1 }
        while upper + 1 < line.count, joins(line[upper].rect, line[upper + 1].rect) { upper += 1 }
        return Array(line[lower...upper])
    }

    /// The bounded block of lines around a hit that could be one paragraph: the
    /// hit's own line run, plus the vertically adjacent lines that are
    /// geometrically compatible with it, in reading order.
    ///
    /// Nothing is guessed from a neighbour that does not qualify:
    ///
    /// - a line that shares its row with another observation is a column or a
    ///   table cell, not half of a wrapped paragraph, so nothing joins to it;
    /// - the vertical gap has to look like ordinary line spacing;
    /// - the two horizontal ranges have to overlap;
    /// - the reading direction has to be the same.
    static func contextLines(containing hit: OCRWord, lines: [OCRLine]) -> [[OCRWord]] {
        // AppKit y grows upward: the top of the capture comes first.
        let ordered = lines
            .filter { !$0.words.isEmpty }
            .sorted { first, second in
                let a = boundingBox(first.words)
                let b = boundingBox(second.words)
                if a.midY != b.midY { return a.midY > b.midY }
                return a.minX < b.minX
            }
        guard let index = ordered.firstIndex(where: { $0.words.contains(hit) }) else { return [] }
        let hitRun = lineRun(containing: hit, words: ordered[index].words)
        guard !hitRun.isEmpty else { return [] }

        var block = [hitRun]
        var anchor = hitRun
        var above = index - 1
        while above >= 0, block.count < maximumContextLines,
              let line = continuation(of: anchor, in: ordered[above], among: ordered) {
            block.insert(line, at: 0)
            anchor = line
            above -= 1
        }
        anchor = hitRun
        var below = index + 1
        while below < ordered.count, block.count < maximumContextLines,
              let line = continuation(of: anchor, in: ordered[below], among: ordered) {
            block.append(line)
            anchor = line
            below += 1
        }
        return block
    }

    /// The real box of a run of words, or zero for no words at all.
    static func boundingBox(_ words: [OCRWord]) -> CGRect {
        guard let first = words.first else { return .zero }
        return words.dropFirst().reduce(first.rect) { $0.union($1.rect) }
    }

    // MARK: - Context geometry

    /// The run of one line that continues `run`, or nil when the two lines are
    /// not one paragraph.
    private static func continuation(of run: [OCRWord], in line: OCRLine, among lines: [OCRLine]) -> [OCRWord]? {
        let box = boundingBox(run)
        guard isAloneInItsBand(run, among: lines),
              let anchor = line.words
                  .filter({ horizontalOverlap($0.rect, box) > 0 })
                  .max(by: { horizontalOverlap($0.rect, box) < horizontalOverlap($1.rect, box) }) else { return nil }
        let candidate = lineRun(containing: anchor, words: line.words)
        guard !candidate.isEmpty, isAloneInItsBand(candidate, among: lines) else { return nil }

        let candidateBox = boundingBox(candidate)
        let candidateIsAbove = candidateBox.midY >= box.midY
        guard isOrdinaryLineSpacing(upper: candidateIsAbove ? candidateBox : box,
                                    lower: candidateIsAbove ? box : candidateBox),
              rangesAreCompatible(candidateBox, box),
              isLeftToRight(candidate),
              isLeftToRight(run) else { return nil }
        return candidate
    }

    /// Whether the line this run came from holds nothing else on its own row.
    /// Two columns or two table cells put a second observation on the same row,
    /// which is what tells a cell apart from a wrapped paragraph line.
    private static func isAloneInItsBand(_ run: [OCRWord], among lines: [OCRLine]) -> Bool {
        guard let first = run.first else { return false }
        let box = boundingBox(run)
        return !lines.contains { line in
            guard !line.words.isEmpty, !line.words.contains(first) else { return false }
            return overlapsVertically(boundingBox(line.words), box)
        }
    }

    private static func horizontalOverlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        min(a.maxX, b.maxX) - max(a.minX, b.minX)
    }

    /// The two runs have to share most of the narrower one: a large horizontal
    /// jump is a different block, not a continuation of the same paragraph.
    private static func rangesAreCompatible(_ a: CGRect, _ b: CGRect) -> Bool {
        let narrower = min(a.width, b.width)
        guard narrower > 0 else { return false }
        return horizontalOverlap(a, b) >= 0.5 * narrower
    }

    private static func isOrdinaryLineSpacing(upper: CGRect, lower: CGRect) -> Bool {
        let height = max(upper.height, lower.height)
        guard height > 0 else { return false }
        let gap = upper.minY - lower.maxY
        return gap >= -0.25 * height && gap <= 0.9 * height
    }

    private static func isLeftToRight(_ run: [OCRWord]) -> Bool {
        zip(run, run.dropFirst()).allSatisfy { $0.rect.midX < $1.rect.midX }
    }

    private static func overlapsVertically(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        let shorter = min(a.height, b.height)
        guard shorter > 0 else { return false }
        return overlap >= shorter / 2
    }

    private static func joins(_ a: CGRect, _ b: CGRect) -> Bool {
        let gap = b.minX - a.maxX
        return gap <= max(3, 0.5 * max(a.height, b.height))
    }
}
