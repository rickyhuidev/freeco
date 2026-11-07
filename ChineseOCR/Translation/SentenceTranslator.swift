import SwiftUI
import Translation

/// Holds sentence-level translations produced by Apple's on-device Translation
/// framework. The actual work is driven by a `.translationTask` modifier in the
/// view layer (that's the only supported entry point for `TranslationSession`).
@Observable
final class SentenceTranslator {
    enum State {
        case idle, translating, done, unavailable
    }

    private(set) var state: State = .idle
    private(set) var translations: [String: String] = [:]

    func translation(for sentence: String) -> String? { translations[sentence] }

    /// Performs batch translation for `sentences` using an active session.
    @MainActor
    func run(sentences: [String], using session: TranslationSession) async {
        guard !sentences.isEmpty else {
            state = .done
            return
        }
        state = .translating
        let requests = sentences.map { TranslationSession.Request(sourceText: $0) }
        do {
            let responses = try await session.translations(from: requests)
            for response in responses {
                translations[response.sourceText] = response.targetText
            }
            state = .done
        } catch {
            state = .unavailable
        }
    }
}
