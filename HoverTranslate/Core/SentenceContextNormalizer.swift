import Foundation

/// 2026-09-19 cross-line sentence design: folds the line breaks of a bounded
/// read before any sentence is looked for.
///
/// A single line break is typography, not a boundary: a sentence that wraps
/// over two lines is still one sentence. Two or more breaks in a row are a
/// paragraph boundary and are copied through untouched, so the resolver can
/// refuse to cross them.
///
/// Every UTF-16 unit of the normalized text remembers the original range it
/// came from. That is what makes the sentence the resolver finds usable: the
/// card anchors on the original range and a bounds query needs it, while the
/// text that is shown and translated is the normalized one.
enum SentenceContextNormalizer {
    /// Normalized text plus the way back to the original offsets.
    struct Normalized: Equatable, Sendable {
        /// The text with every single line break folded into one space.
        let text: String
        /// One entry per UTF-16 unit of `text`: the original range it came
        /// from. A folded break maps to the whole run it replaced.
        private let origins: [NSRange]

        fileprivate init(text: String, origins: [NSRange]) {
            self.text = text
            self.origins = origins
        }

        /// The original range `range` covers, or nil when the range is not
        /// inside the text.
        func originalRange(forNormalized range: NSRange) -> NSRange? {
            guard range.location >= 0, range.length > 0,
                  range.location + range.length <= origins.count else { return nil }
            let first = origins[range.location]
            let last = origins[range.location + range.length - 1]
            return NSRange(location: first.location,
                           length: last.location + last.length - first.location)
        }

        /// Where one original offset ended up. An offset inside a folded break
        /// maps to the single space that replaced it.
        func normalizedOffset(forOriginal offset: Int) -> Int? {
            origins.firstIndex { $0.location <= offset && offset < $0.location + $0.length }
        }
    }

    static func normalize(_ text: String) -> Normalized {
        let source = text as NSString
        var units: [unichar] = []
        var origins: [NSRange] = []
        units.reserveCapacity(source.length)
        origins.reserveCapacity(source.length)

        var index = 0
        while index < source.length {
            guard isWhitespace(source.character(at: index)) else {
                units.append(source.character(at: index))
                origins.append(NSRange(location: index, length: 1))
                index += 1
                continue
            }
            var end = index
            var breaks = 0
            while end < source.length, isWhitespace(source.character(at: end)) {
                let unit = source.character(at: end)
                if isLineBreak(unit) {
                    breaks += 1
                    // A CR LF pair is one line ending, not a paragraph break.
                    if unit == 0x0D, end + 1 < source.length, source.character(at: end + 1) == 0x0A {
                        end += 1
                    }
                }
                end += 1
            }
            if breaks == 1 {
                units.append(0x20)
                origins.append(NSRange(location: index, length: end - index))
            } else {
                for offset in index..<end {
                    units.append(source.character(at: offset))
                    origins.append(NSRange(location: offset, length: 1))
                }
            }
            index = end
        }
        return Normalized(text: String(utf16CodeUnits: units, count: units.count), origins: origins)
    }

    private static func isWhitespace(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    private static func isLineBreak(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.newlines.contains(scalar)
    }
}
