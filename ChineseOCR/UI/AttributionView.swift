import SwiftUI

/// Required attribution for CC-CEDICT (CC BY-SA 4.0).
struct AttributionView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Freeco")
                    .font(.title2.weight(.semibold))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Dictionary")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(1.2)
                        .foregroundStyle(.tertiary)
                    Text("Pinyin and English definitions come from CC-CEDICT, a community-maintained Chinese–English dictionary published by MDBG. Based on CEDICT © 1997, 1998 Paul Andrew Denisowski.")
                    Text("CC-CEDICT is licensed under the Creative Commons Attribution-ShareAlike 4.0 International License. The bundled copy was reformatted (fields reordered into tab-separated columns) but its content is unchanged.")
                        .foregroundStyle(.secondary)
                    Link("cc-cedict.org", destination: URL(string: "https://cc-cedict.org/wiki/")!)
                    Link("CC BY-SA 4.0 license", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recognition & translation")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(1.2)
                        .foregroundStyle(.tertiary)
                    Text("Text recognition uses Apple Vision and sentence translation uses Apple Translation, both on-device.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
