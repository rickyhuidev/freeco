import SwiftUI

/// Speaker icon that reads `text` aloud with the selected Mandarin voice, and
/// turns into a stop button while that text is playing.
struct SpeakButton: View {
    let text: String
    let accessibilityLabel: String

    var body: some View {
        let isPlaying = SpeechService.shared.currentText == text
        Button {
            SpeechService.shared.toggle(text)
        } label: {
            Image(systemName: SpeakButton.symbol(isPlaying: isPlaying))
                .font(.system(size: 17))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Stop" : accessibilityLabel)
    }

    static func symbol(isPlaying: Bool) -> String {
        isPlaying ? "stop.fill" : "speaker.wave.2.fill"
    }
}
