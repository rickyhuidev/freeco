import SwiftUI

/// Pinyin + English for a tapped word. Several CC-CEDICT entries can share a
/// headword (polyphones, surnames, variants); each is shown with its own pinyin.
struct WordDetail: View {
    let word: String
    let entries: [DictionaryEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(word)
                    .font(Theme.Font.hanzi(52))
                    .textSelection(.enabled)
                if let variant = variantForm {
                    Text(variant)
                        .font(Theme.Font.hanzi(24))
                        .foregroundStyle(.tertiary)
                }
            }

            if entries.isEmpty {
                Text("Not in dictionary")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.pinyin)
                            .font(Theme.Font.pinyin(22))
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(entry.definitions.enumerated()), id: \.offset) { _, definition in
                                Text(definition)
                                    .font(.body)
                                    .foregroundStyle(.primary.opacity(0.88))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    /// The other script's form (traditional when the scan was simplified, and vice versa).
    private var variantForm: String? {
        guard let first = entries.first, first.hasVariant else { return nil }
        return word == first.simplified ? first.traditional : first.simplified
    }
}
