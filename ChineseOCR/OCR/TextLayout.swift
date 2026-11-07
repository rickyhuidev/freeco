import CoreGraphics
import Foundation

/// One recognized line with its normalized Vision box (origin bottom-left).
struct RecognizedLine {
    let text: String
    let box: CGRect
}

/// Turns Vision's visual lines into paragraphs and sentences for translation.
enum TextLayout {
    private static let terminators: Set<Character> = ["。", "！", "？", "!", "?", "…", "；", ";"]
    /// Closing quotes/brackets that belong to the sentence they follow.
    private static let closers: Set<Character> = ["」", "』", "”", "’", "\"", "'", "）", ")", "》", "〉"]

    /// A wrapped line fills its column, so shorter lines are treated as standalone
    /// (menu items, labels) even when stacked tightly.
    private static let minWrappedLineLength = 6

    /// Joins lines that are a wrapped continuation of the line above: same column,
    /// directly below, similar text size, the line above fills the column, and it
    /// doesn't end a sentence. Unrelated lines such as menu items stay separate.
    /// `imageAspect` is width / height of the image, so x and y share units.
    static func paragraphs(from lines: [RecognizedLine], imageAspect: CGFloat) -> [String] {
        var paragraphs: [String] = []
        var current = ""
        var previous: (box: CGRect, charWidth: CGFloat, length: Int)?

        for line in lines {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            let box = CGRect(x: line.box.minX * imageAspect, y: line.box.minY,
                             width: line.box.width * imageAspect, height: line.box.height)
            let charWidth = box.width / CGFloat(text.count)

            if let previous,
               previous.length >= minWrappedLineLength,
               !endsSentence(current),
               continues(previous.box, previous.charWidth, below: box, charWidth) {
                current += text
            } else {
                if !current.isEmpty { paragraphs.append(current) }
                current = text
            }
            previous = (box, charWidth, text.count)
        }
        if !current.isEmpty { paragraphs.append(current) }
        return paragraphs
    }

    /// Splits text into sentences after terminal punctuation, keeping any closing
    /// quote or bracket with the sentence it ends. Newlines also break sentences.
    static func sentences(in text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        var justTerminated = false

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { sentences.append(trimmed) }
            current = ""
        }

        for ch in text {
            if ch == "\n" {
                flush()
                justTerminated = false
                continue
            }
            if justTerminated, !closers.contains(ch), !terminators.contains(ch) {
                flush()
            }
            current.append(ch)
            justTerminated = terminators.contains(ch) || (justTerminated && closers.contains(ch))
        }
        flush()
        return sentences
    }

    private static func endsSentence(_ text: String) -> Bool {
        guard let last = text.last(where: { !closers.contains($0) }) else { return false }
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