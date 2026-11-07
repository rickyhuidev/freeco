import CoreGraphics
import Foundation

/// One recognized line with its normalized Vision box (origin bottom-left).
struct RecognizedLine {
    let text: String
    let box: CGRect
}

/// Where a word sits: which sentence, and its character range within it.
struct SentenceRef: Equatable {
    let index: Int
    let range: Range<Int>
}

/// The sentences found on a page, plus a lookup from a word's position in its
/// line to the sentence containing it.
struct SentenceMap {
    fileprivate(set) var sentences: [String] = []
    /// For each line: its character offset within its paragraph, and that paragraph.
    fileprivate var lineStarts: [Int: (offset: Int, paragraph: Int)] = [:]
    /// For each paragraph: its sentences' indices and character bounds.
    fileprivate var spans: [[(index: Int, bounds: Range<Int>)]] = []

    func sentence(line: Int, characterOffset: Int, length: Int) -> SentenceRef? {
        guard let start = lineStarts[line] else { return nil }
        let position = start.offset + characterOffset
        guard let span = spans[start.paragraph].first(where: { $0.bounds.contains(position) })
        else { return nil }
        let lower = position - span.bounds.lowerBound
        return SentenceRef(index: span.index, range: lower..<(lower + length))
    }
}

/// Turns Vision's visual lines into paragraphs and sentences for translation.
enum TextLayout {
    private static let terminators: Set<Character> = ["。", "！", "？", "!", "?", "…", "；", ";"]
    /// Closing quotes/brackets that belong to the sentence they follow.
    private static let closers: Set<Character> = ["」", "』", "”", "’", "\"", "'", "）", ")", "》", "〉"]

    /// A wrapped line fills its column, so shorter lines are treated as standalone
    /// (menu items, labels) even when stacked tightly.
    private static let minWrappedLineLength = 6

    /// Builds the page's sentences. Only sentences containing Chinese are kept,
    /// since those are the only ones a tapped word can belong to.
    static func sentenceMap(from lines: [RecognizedLine], imageAspect: CGFloat) -> SentenceMap {
        var map = SentenceMap()
        for group in paragraphs(from: lines, imageAspect: imageAspect) {
            let paragraph = map.spans.count
            var text = ""
            for line in group {
                map.lineStarts[line] = (text.count, paragraph)
                text += lines[line].text
            }
            var spans: [(index: Int, bounds: Range<Int>)] = []
            for range in sentenceRanges(in: text) {
                let sentence = text[range]
                guard sentence.contains(where: ChineseDictionary.isChinese) else { continue }
                let lower = text.distance(from: text.startIndex, to: range.lowerBound)
                spans.append((map.sentences.count, lower..<(lower + sentence.count)))
                map.sentences.append(String(sentence))
            }
            map.spans.append(spans)
        }
        return map
    }

    /// Groups lines (as indices into `lines`) into paragraphs. A line joins the one
    /// above when it's a wrapped continuation: same column, directly below, similar
    /// text size, the line above fills the column, and it doesn't end a sentence.
    /// Unrelated lines such as menu items stay separate.
    /// `imageAspect` is width / height of the image, so x and y share units.
    static func paragraphs(from lines: [RecognizedLine], imageAspect: CGFloat) -> [[Int]] {
        var paragraphs: [[Int]] = []
        var current: [Int] = []
        var currentText = ""
        var previous: (box: CGRect, charWidth: CGFloat, length: Int)?

        for (index, line) in lines.enumerated() {
            let text = line.text
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let box = CGRect(x: line.box.minX * imageAspect, y: line.box.minY,
                             width: line.box.width * imageAspect, height: line.box.height)
            let charWidth = box.width / CGFloat(text.count)

            if let previous,
               previous.length >= minWrappedLineLength,
               !endsSentence(currentText),
               continues(previous.box, previous.charWidth, below: box, charWidth) {
                current.append(index)
                currentText += text
            } else {
                if !current.isEmpty { paragraphs.append(current) }
                current = [index]
                currentText = text
            }
            previous = (box, charWidth, text.count)
        }
        if !current.isEmpty { paragraphs.append(current) }
        return paragraphs
    }

    /// Splits text into sentences after terminal punctuation, keeping any closing
    /// quote or bracket with the sentence it ends. Ranges exclude surrounding spaces.
    static func sentenceRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start = text.startIndex
        var justTerminated = false

        func flush(upTo end: String.Index) {
            var lower = start, upper = end
            while lower < upper, text[lower].isWhitespace { lower = text.index(after: lower) }
            while upper > lower, text[text.index(before: upper)].isWhitespace { upper = text.index(before: upper) }
            if lower < upper { ranges.append(lower..<upper) }
        }

        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            if justTerminated, !closers.contains(ch), !terminators.contains(ch) {
                flush(upTo: i)
                start = i
            }
            justTerminated = terminators.contains(ch) || (justTerminated && closers.contains(ch))
            i = text.index(after: i)
        }
        flush(upTo: text.endIndex)
        return ranges
    }

    private static func endsSentence(_ text: String) -> Bool {
        guard let last = text.last(where: { !closers.contains($0) && !$0.isWhitespace }) else { return false }
        return terminators.contains(last)
    }

    /// Measures in character widths: Chinese glyphs and punctuation are about one
    /// em wide, which is far steadier than Vision's line-box heights.
    private static func continues(_ previous: CGRect, _ previousCharWidth: CGFloat,
                                  below next: CGRect, _ nextCharWidth: CGFloat) -> Bool {
        let em = max(previousCharWidth, nextCharWidth)
        guard em > 0, min(previousCharWidth, nextCharWidth) / em > 0.8 else { return false }
        // Vision's y grows upward, so the next line's top sits just under the previous bottom.
        let gap = previous.minY - next.maxY
        guard gap > -0.5 * em, gap < 1.2 * em else { return false }
        // Allow a first-line indent of about two characters.
        guard abs(next.minX - previous.minX) < 2.5 * em else { return false }
        // The wrapped line reaches the column's right edge, so it extends at least
        // as far right as the line that continues it.
        return previous.maxX >= next.maxX - em
    }
}
