import SwiftUI

/// Picks the Mandarin voice used for pronunciation. Voices that aren't downloaded
/// are listed but not selectable, since only iOS Settings can install them.
struct VoiceSettingsView: View {
    @AppStorage(SpeechService.voiceKey) private var selectedID = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var voices: [MandarinVoice] = []
    @State private var automaticName: String?

    private static let preview = "你好，欢迎学习中文。"

    /// iOS 26 renamed Accessibility > Spoken Content to Read & Speak.
    private static var speechSettingsName: String {
        if #available(iOS 26, *) { "Read & Speak" } else { "Spoken Content" }
    }

    /// A saved voice that has since been deleted falls back to Automatic.
    private var effectiveSelection: String {
        voices.contains { $0.identifier == selectedID } ? selectedID : ""
    }

    private var automaticDetail: String {
        automaticName.map { "Best installed voice (\($0))" } ?? "Best installed voice"
    }

    var body: some View {
        List {
            Section {
                row(title: "Automatic", detail: automaticDetail, id: "")
                ForEach(voices.filter { !$0.isNovelty }) { voice in
                    voiceRow(voice)
                }
            } header: {
                Text("Standard")
            } footer: {
                Text("Download more voices in Settings > Accessibility > \(Self.speechSettingsName) > Voices > Chinese.")
            }

            let novelty = voices.filter(\.isNovelty)
            if !novelty.isEmpty {
                Section {
                    ForEach(novelty) { voice in
                        voiceRow(voice)
                    }
                } header: {
                    Text("Novelty")
                } footer: {
                    Text("Novelty voices are built into iOS. They sound robotic but need no download.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .onAppear(perform: reload)
        .onDisappear { SpeechService.shared.stop() }
        // Picks up voices downloaded in Settings while the app was in the background.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reload() }
        }
    }

    private func reload() {
        voices = MandarinVoices.all()
        automaticName = MandarinVoices.bestInstalled()?.name
    }

    @ViewBuilder
    private func voiceRow(_ voice: MandarinVoice) -> some View {
        if let identifier = voice.identifier {
            row(title: voice.name, detail: voice.detail, id: identifier)
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(voice.name)
                    Text(voice.detail).font(.caption)
                }
                Spacer()
                Text("Not downloaded").font(.caption)
            }
            .foregroundStyle(.tertiary)
            .listRowBackground(Color.white.opacity(0.04))
        }
    }

    private func row(title: String, detail: String, id: String) -> some View {
        Button {
            selectedID = id
            SpeechService.shared.speak(Self.preview, voiceIdentifier: id)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if effectiveSelection == id {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .listRowBackground(Color.white.opacity(0.08))
    }
}
