import Foundation

/// Converts CC-CEDICT's numeric pinyin (e.g. "chuan2 tong3") into tone-marked
/// pinyin (e.g. "chuán tǒng"). CC-CEDICT stores one syllable per space-separated
/// token with a trailing tone digit 1-5 (5 = neutral tone, no mark).
enum PinyinFormatter {
    private static let toneMarks: [Character: [Character]] = [
        "a": ["ā", "á", "ǎ", "à"],
        "e": ["ē", "é", "ě", "è"],
        "i": ["ī", "í", "ǐ", "ì"],
        "o": ["ō", "ó", "ǒ", "ò"],
        "u": ["ū", "ú", "ǔ", "ù"],
        "ü": ["ǖ", "ǘ", "ǚ", "ǜ"],
    ]

    static func diacritic(for numbered: String) -> String {
        numbered
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { syllable(String($0)) }
            .joined(separator: " ")
    }

    private static func syllable(_ raw: String) -> String {
        var s = raw
            .replacingOccurrences(of: "u:", with: "ü")
            .replacingOccurrences(of: "U:", with: "Ü")

        guard let last = s.last, let tone = last.wholeNumberValue, (1...5).contains(tone) else {
            // No tone digit (proper nouns, punctuation like "·"): just normalize v.
            return s.replacingOccurrences(of: "v", with: "ü").replacingOccurrences(of: "V", with: "Ü")
        }
        s.removeLast()
        s = s.replacingOccurrences(of: "v", with: "ü").replacingOccurrences(of: "V", with: "Ü")
        if tone == 5 { return s } // neutral tone: no mark

        var chars = Array(s)
        guard let idx = markIndex(chars) else { return s }
        let wasUpper = chars[idx].isUppercase
        let vowel = Character(chars[idx].lowercased())
        guard let marks = toneMarks[vowel] else { return s }
        var mark = marks[tone - 1]
        if wasUpper { mark = Character(mark.uppercased()) }
        chars[idx] = mark
        return String(chars)
    }

    /// Standard tone-placement rules: a/e win; otherwise the o in "ou";
    /// otherwise the last vowel in the syllable.
    private static func markIndex(_ chars: [Character]) -> Int? {
        guard !chars.isEmpty else { return nil }
        let lower = chars.map { Character($0.lowercased()) }
        if let i = lower.firstIndex(of: "a") { return i }
        if let i = lower.firstIndex(of: "e") { return i }
        if lower.count >= 2 {
            for i in 0..<(lower.count - 1) where lower[i] == "o" && lower[i + 1] == "u" {
                return i
            }
        }
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "ü"]
        return lower.lastIndex(where: { vowels.contains($0) })
    }
}
