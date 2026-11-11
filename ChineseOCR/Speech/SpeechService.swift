import AVFoundation
import Observation
import UIKit

/// Speaks Chinese text with the on-device synthesizer. One shared instance, because
/// an `AVSpeechSynthesizer` stops talking as soon as it's deallocated.
@MainActor
@Observable
final class SpeechService: NSObject {
    static let shared = SpeechService()

    /// UserDefaults key for the chosen voice identifier. Empty means automatic.
    static let voiceKey = "speechVoiceIdentifier"

    /// The text being spoken (or about to be), so its button can show a stop icon.
    private(set) var currentText: String?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()

    /// AVAudioSession calls block, so they stay off the main thread. Serial keeps
    /// activate/deactivate in order.
    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "SpeechService.audioSession")

    /// Bumped on every request. Only the latest request plays, and the session is
    /// only deactivated if no request arrived since speech ended.
    @ObservationIgnored private var generation = 0

    /// The utterance for `currentText`, so callbacks from interrupted ones are ignored.
    @ObservationIgnored private var currentUtterance: AVSpeechUtterance?

    /// Grace period before releasing the session, so quick repeat taps don't
    /// deactivate it underneath the next utterance.
    private static let deactivationDelay: TimeInterval = 0.5

    private override init() {
        super.init()
        synthesizer.delegate = self
        // iOS cuts audio when the app suspends; stop cleanly so no stop icon is left on.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { SpeechService.shared.stop() }
        }
        sessionQueue.async {
            // .playback so pronunciation is audible with the silent switch on.
            try? AVAudioSession.sharedInstance()
                .setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        }
    }

    /// Stops `text` if it's the one playing, otherwise speaks it.
    func toggle(_ text: String) {
        if currentText == text { stop() } else { speak(text) }
    }

    /// Speaks `text`, interrupting anything already playing. `voiceIdentifier`
    /// overrides the saved choice (used for previews).
    func speak(_ text: String, voiceIdentifier: String? = nil) {
        // Unconditional: `isSpeaking` stays false briefly after `speak(_:)`, so
        // checking it first lets rapid taps queue up a backlog of utterances.
        synthesizer.stopSpeaking(at: .immediate)
        generation += 1
        let request = generation
        currentText = text
        currentUtterance = nil
        let identifier = voiceIdentifier ?? UserDefaults.standard.string(forKey: Self.voiceKey)

        sessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(true)
            // GCD rather than a Task: AVSpeechSynthesizer logs "unsafeForcedSync"
            // warnings when called from a Swift concurrency context.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard request == self.generation else { return }
                    let utterance = AVSpeechUtterance(string: text)
                    utterance.voice = self.resolveVoice(identifier)
                    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
                    self.currentUtterance = utterance
                    self.synthesizer.speak(utterance)
                }
            }
        }
    }

    /// Stops any speech, including a request that hasn't started yet.
    func stop() {
        guard currentText != nil else { return }
        generation += 1
        currentText = nil
        currentUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        scheduleDeactivation()
    }

    /// The requested voice if it's still installed, else the best installed one.
    private func resolveVoice(_ identifier: String?) -> AVSpeechSynthesisVoice? {
        if let identifier, !identifier.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice
        }
        return MandarinVoices.bestInstalled() ?? AVSpeechSynthesisVoice(language: MandarinVoices.language)
    }

    private func utteranceEnded(_ utterance: AVSpeechUtterance) {
        guard utterance === currentUtterance else { return }
        currentText = nil
        currentUtterance = nil
        scheduleDeactivation()
    }

    private func scheduleDeactivation() {
        let request = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.deactivationDelay) {
            MainActor.assumeIsolated {
                guard request == self.generation, !self.synthesizer.isSpeaking else { return }
                self.sessionQueue.async {
                    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                }
            }
        }
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        ended(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        ended(utterance)
    }

    /// Only compared by identity on the main thread, never mutated.
    private nonisolated func ended(_ utterance: AVSpeechUtterance) {
        nonisolated(unsafe) let utterance = utterance
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.utteranceEnded(utterance) }
        }
    }
}
