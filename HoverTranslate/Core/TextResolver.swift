import Foundation

/// Finds the word that contains a UTF-16 offset inside a bounded text window.
///
/// Accessibility reports character offsets in UTF-16 code units, so every
/// calculation here works on the UTF-16 view and never on Swift `String`
/// indices. Whitespace, punctuation and invalid offsets return nil instead of
/// guessing a neighbouring word.
enum TextResolver {
    static func word(in text: String, atUTF16Offset offset: Int) -> String? {
        guard let range = wordRange(in: text, atUTF16Offset: offset) else { return nil }
        return (text as NSString).substring(with: range)
    }

    static func wordRange(in text: String, atUTF16Offset offset: Int) -> NSRange? {
        let text = text as NSString
        guard offset >= 0, offset < text.length else { return nil }
        guard isWordCharacter(text.character(at: offset)) else { return nil }

        var start = offset
        while start > 0, isWordCharacter(text.character(at: start - 1)) { start -= 1 }
        var end = offset + 1
        while end < text.length, isWordCharacter(text.character(at: end)) { end += 1 }

        // Absorb an internal apostrophe or hyphen only when it joins characters
        // on both sides, so "don't" and "well-known" stay one word.
        while end < text.length, isJoiner(text.character(at: end)),
              end + 1 < text.length, isWordCharacter(text.character(at: end + 1)) {
            end += 1
            while end < text.length, isWordCharacter(text.character(at: end)) { end += 1 }
        }
        while start > 0, isJoiner(text.character(at: start - 1)),
              start - 2 >= 0, isWordCharacter(text.character(at: start - 2)) {
            start -= 1
            while start > 0, isWordCharacter(text.character(at: start - 1)) { start -= 1 }
        }
        return NSRange(location: start, length: end - start)
    }

    static func isWordCharacter(_ unit: unichar) -> Bool {
        // A lone surrogate is not a letter, so emoji pairs bound a word correctly.
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return TextResolver.wordScalars.contains(scalar)
    }

    private static let wordScalars: CharacterSet = {
        var set = CharacterSet.letters
        set.formUnion(CharacterSet.decimalDigits)
        // Combining marks keep decomposed text such as "café" in one word.
        set.formUnion(CharacterSet.nonBaseCharacters)
        return set
    }()

    private static func isJoiner(_ unit: unichar) -> Bool {
        switch unit {
        case 0x0027, 0x2019, 0x2018, 0x002D, 0x2010, 0x2011:
            return true
        default:
            return false
        }
    }
}
