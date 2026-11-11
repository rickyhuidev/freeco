import AVFoundation

/// A Mandarin voice the user can pick, installed or not.
struct MandarinVoice: Identifiable {
    let name: String
    let gender: AVSpeechSynthesisVoiceGender
    let quality: AVSpeechSynthesisVoiceQuality
    /// `AVSpeechSynthesisVoice.identifier`; nil when the voice isn't downloaded.
    let identifier: String?
    /// Eloquence voices (Eddy, Flo, Grandpa, ...): always installed, robotic-sounding.
    let isNovelty: Bool

    var id: String { identifier ?? "\(name).\(quality.rawValue)" }
    var isInstalled: Bool { identifier != nil }

    /// e.g. "Female · Premium". Gender is omitted when unknown.
    var detail: String {
        let qualityLabel = switch quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: "Default"
        }
        let genderLabel: String? = switch gender {
        case .male: "Male"
        case .female: "Female"
        default: nil
        }
        return [genderLabel, qualityLabel].compactMap { $0 }.joined(separator: " · ")
    }
}

enum MandarinVoices {
    static let language = "zh-CN"

    /// Downloadable zh-CN voices offered in Settings > Accessibility > Read & Speak.
    /// iOS only reports installed voices, so this list is what lets missing ones be
    /// shown (greyed out). Matched by name + quality because identifier formats
    /// differ between OS versions. Update when Apple adds voices.
    private static let catalog: [(name: String, gender: AVSpeechSynthesisVoiceGender, quality: AVSpeechSynthesisVoiceQuality)] = [
        ("Tingting", .female, .default),
        ("Tingting", .female, .enhanced),
        ("Lili", .female, .premium),
        ("Yu-shu", .female, .default),
        ("Li-mu", .male, .default),
    ]

    /// Eloquence voices report `.unspecified`; these are their evident genders.
    private static let noveltyGenders: [String: AVSpeechSynthesisVoiceGender] = [
        "Eddy": .male, "Reed": .male, "Rocko": .male, "Grandpa": .male,
        "Flo": .female, "Sandy": .female, "Shelley": .female, "Grandma": .female,
    ]

    private static func isNovelty(_ voice: AVSpeechSynthesisVoice) -> Bool {
        voice.identifier.contains(".eloquence.")
    }

    /// Installed zh-CN voices, de-duplicated by identifier.
    private static func installed() -> [AVSpeechSynthesisVoice] {
        var seen = Set<String>()
        return AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == language && seen.insert($0.identifier).inserted
        }
    }

    /// Best installed non-novelty voice, used when the user hasn't picked one.
    static func bestInstalled() -> AVSpeechSynthesisVoice? {
        installed()
            .filter { !isNovelty($0) }
            .max { $0.quality.rawValue < $1.quality.rawValue }
    }

    /// Catalog entries (with install status) plus any installed voice the catalog
    /// doesn't know about. Installed first, then by quality.
    static func all() -> [MandarinVoice] {
        var remaining = installed()
        var voices: [MandarinVoice] = catalog.map { entry in
            let match = remaining.firstIndex { $0.name == entry.name && $0.quality == entry.quality }
                .map { remaining.remove(at: $0) }
            return MandarinVoice(name: entry.name, gender: entry.gender, quality: entry.quality,
                                 identifier: match?.identifier, isNovelty: false)
        }
        voices += remaining.map { voice in
            let gender = voice.gender != .unspecified ? voice.gender : (noveltyGenders[voice.name] ?? .unspecified)
            return MandarinVoice(name: voice.name, gender: gender, quality: voice.quality,
                                 identifier: voice.identifier, isNovelty: isNovelty(voice))
        }
        return voices.sorted {
            if $0.isInstalled != $1.isInstalled { return $0.isInstalled }
            if $0.quality != $1.quality { return $0.quality.rawValue > $1.quality.rawValue }
            return $0.name < $1.name
        }
    }
}
