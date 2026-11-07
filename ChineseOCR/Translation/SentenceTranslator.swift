import SwiftUI
import Translation

/// Holds sentence-level translations produced by Apple's on-device Translation
/// framework. The actual work is driven by a `.translationTask` modifier in the
/// view layer (that's the only supported entry point for `TranslationSession`).
@Observable
final class SentenceTranslator {
    enum State: Equatable {
        case idle
        case translating
        case done
        case unavailable(String)
    }

    var state: State = .idle
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
        let requests = sentences.enumerated().map { index, text in
            TranslationSession.Request(sourceText: text, clientIdentifier: String(index))
        }
        do {
            let responses = try await session.translations(from: requests)
            var map = translations
            for response in responses {
                if let id = response.clientIdentifier, let i = Int(id), i < sentences.count {
                    map[sentences[i]] = response.targetText
                } else {
                    map[response.sourceText] = response.targetText
                }
            }
            translations = map
            state = .done
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }
}
