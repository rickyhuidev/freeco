import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// A single CC-CEDICT entry.
struct DictionaryEntry: Identifiable {
    /// Position in the dictionary file, unique per entry.
    let id: Int
    let simplified: String
    let traditional: String
    let pinyinNumbered: String
    let definitions: [String]

    var pinyin: String { PinyinFormatter.diacritic(for: pinyinNumbered) }

    /// Whether the simplified and traditional forms differ (worth showing both).
    var hasVariant: Bool { simplified != traditional }
}

/// One token of segmented text. `isWord` means a tappable Chinese unit.
struct TextSegment {
    let text: String
    /// Range within the source line, used to query Vision for a bounding box.
    let range: Range<String.Index>
    let isWord: Bool
}

/// Loads CC-CEDICT from the asset catalog and provides segmentation + lookup.
/// Lookup is keyed by both simplified and traditional forms so either script works.
/// All mutable state is written once, on `loadQueue`, before any reads.
final class ChineseDictionary: @unchecked Sendable {
    static let shared = ChineseDictionary()

    private var entries: [DictionaryEntry] = []
    private var index: [String: [Int]] = [:]
    private var maxWordLength = 1

    private let loadQueue = DispatchQueue(label: "dictionary.load", qos: .userInitiated)
    private var isLoaded = false

    private init() {}

    // MARK: Loading

    /// Idempotent, safe to call from several places. Returns once the dictionary
    /// is usable. Parsing ~125k entries takes well under a second.
    func ensureLoaded() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            loadQueue.async { [weak self] in
                if let self, !self.isLoaded {
                    if let asset = NSDataAsset(name: "cedict") {
                        self.load(tsv: String(decoding: asset.data, as: UTF8.self))
                    } else {
                        assertionFailure("cedict data asset missing")
                        self.isLoaded = true
                    }
                }
                cont.resume()
            }
        }
    }

    /// Parses the bundled TSV (`simplified, traditional, pinyin, defs`). Called on
    /// `loadQueue` by `ensureLoaded`; the Mac check script calls it directly.
    func load(tsv text: String) {
        var parsedEntries: [DictionaryEntry] = []
        parsedEntries.reserveCapacity(130_000)
        var parsedIndex: [String: [Int]] = [:]
        parsedIndex.reserveCapacity(260_000)
        var maxLen = 1

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 4 else { continue }
            let simp = String(fields[0])
            let trad = String(fields[1])
            let entryIndex = parsedEntries.count
            parsedEntries.append(DictionaryEntry(
                id: entryIndex,
                simplified: simp,
                traditional: trad,
                pinyinNumbered: String(fields[2]),
                definitions: fields[3].split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            ))
            parsedIndex[simp, default: []].append(entryIndex)
            if trad != simp {
                parsedIndex[trad, default: []].append(entryIndex)
            }
            maxLen = max(maxLen, simp.count, trad.count)
        }

        entries = parsedEntries
        index = parsedIndex
        // Cap the matching window: real words are short; this bounds segmentation cost.
        maxWordLength = min(maxLen, 12)
        isLoaded = true
    }

    // MARK: Lookup

    func entries(for word: String) -> [DictionaryEntry] {
        guard let idxs = index[word] else { return [] }
        return idxs.map { entries[$0] }
    }

    // MARK: Segmentation

    /// Forward maximum-matching segmentation against the CC-CEDICT headword set.
    /// Chinese runs become longest dictionary words (falling back to single
    /// characters); non-Chinese runs become single non-tappable segments.
    func segment(_ line: String) -> [TextSegment] {
        let chars = Array(line)
        let n = chars.count
        guard n > 0 else { return [] }

        // Precompute String.Index for every character boundary (+ end sentinel).
        var boundaries: [String.Index] = []
        boundaries.reserveCapacity(n + 1)
        var cursor = line.startIndex
        for _ in 0..<n {
            boundaries.append(cursor)
            cursor = line.index(after: cursor)
        }
        boundaries.append(line.endIndex)

        var result: [TextSegment] = []
        var i = 0
        while i < n {
            if Self.isChinese(chars[i]) {
                var matched = 1
                var k = min(maxWordLength, n - i)
                while k > 1 {
                    if index[String(chars[i..<(i + k)])] != nil {
                        matched = k
                        break
                    }
                    k -= 1
                }
                let range = boundaries[i]..<boundaries[i + matched]
                result.append(TextSegment(text: String(chars[i..<(i + matched)]), range: range, isWord: true))
                i += matched
            } else {
                var j = i
                while j < n && !Self.isChinese(chars[j]) { j += 1 }
                let range = boundaries[i]..<boundaries[j]
                result.append(TextSegment(text: String(chars[i..<j]), range: range, isWord: false))
                i = j
            }
        }
        return result
    }

    static func isChinese(_ c: Character) -> Bool {
        for scalar in c.unicodeScalars {
            let v = scalar.value
            let isHan = (0x4E00...0x9FFF).contains(v) // CJK Unified Ideographs
                || (0x3400...0x4DBF).contains(v)      // Extension A
                || (0x20000...0x2A6DF).contains(v)    // Extension B
                || (0xF900...0xFAFF).contains(v)      // Compatibility Ideographs
            if !isHan { return false }
        }
        return true
    }
}
