import AVFoundation

/// T57 — display-language-name → speech-locale resolution for
/// `ReadAloudController`. Ports the table half of Flutter's
/// `lib/utils/speech_locales.dart` (the TTS-relevant half only; that file's
/// speech-*recognition* helpers have no native counterpart yet since T59
/// Voice hasn't landed). **English means Indian English** for the same
/// reason the Dart doc comment gives: the audience is Indian, so `en`
/// resolves to `en-IN`, not `en-US`.
enum SpeechLocales {
    static let defaultLocale = "en-IN"
    static let fallbackLocale = "en-US"

    /// `BibleLanguage.language` display name (e.g. "English", "Telugu") →
    /// ISO 639-1 code. Keys match `_isoByLanguageName` in the Dart source
    /// exactly — these are the same content-language names the backend
    /// returns everywhere in this app, not a Bible-specific set.
    private static let isoByLanguageName: [String: String] = [
        "english": "en",
        "hindi": "hi",
        "telugu": "te",
        "tamil": "ta",
        "kannada": "kn",
        "malayalam": "ml",
        "bengali": "bn",
        "bangla": "bn",
        "gujarati": "gu",
        "marathi": "mr",
        "punjabi": "pa",
        "odia": "or",
        "oriya": "or",
        "assamese": "as",
        "urdu": "ur",
    ]

    /// ISO 639-1 → locale tag, ported verbatim from `_localeByIso`.
    private static let localeByISO: [String: String] = [
        "en": "en-IN",
        "hi": "hi-IN",
        "te": "te-IN",
        "ta": "ta-IN",
        "kn": "kn-IN",
        "ml": "ml-IN",
        "bn": "bn-IN",
        "gu": "gu-IN",
        "mr": "mr-IN",
        "pa": "pa-IN",
        "or": "or-IN",
        "as": "as-IN",
        "ur": "ur-IN",
        "ar": "ar-SA",
        "zh": "zh-CN",
        "ja": "ja-JP",
        "ko": "ko-KR",
        "es": "es-ES",
        "fr": "fr-FR",
        "de": "de-DE",
        "pt": "pt-BR",
        "ru": "ru-RU",
        "it": "it-IT",
        "id": "id-ID",
        "th": "th-TH",
        "vi": "vi-VN",
    ]

    /// Bare language part of any locale form (`te_IN` / `te-IN` / `te` →
    /// `te`), ported from `isoOf`.
    static func iso(ofLocale locale: String) -> String? {
        let trimmed = locale.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)
    }

    /// Resolves a Bible-content language display name to the best
    /// `AVSpeechSynthesisVoice` this device has, ranked by quality
    /// (`.premium` > `.enhanced` > `.default`) — ports `_applyBestVoice`'s
    /// "both engines default to the flat compact voice" reasoning, minus
    /// Dart's Android-only `network_required`/`notInstalled` scoring (no
    /// native equivalent field on `AVSpeechSynthesisVoice`).
    static func bestVoice(forLanguageName languageName: String) -> AVSpeechSynthesisVoice? {
        let iso = isoByLanguageName[languageName.trimmingCharacters(in: .whitespaces).lowercased()]
        let tag = iso.map { localeByISO[$0] ?? $0 }
        let candidates = [tag, defaultLocale, fallbackLocale].compactMap { $0 }

        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        for candidate in candidates {
            let targetISO = SpeechLocales.iso(ofLocale: candidate)
            let matches = allVoices.filter { SpeechLocales.iso(ofLocale: $0.language) == targetISO }
            if let best = matches.max(by: { qualityRank($0.quality) < qualityRank($1.quality) }) {
                return best
            }
        }
        return AVSpeechSynthesisVoice(language: defaultLocale)
    }

    private static func qualityRank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
        switch quality {
        case .premium: 3
        case .enhanced: 2
        case .default: 1
        @unknown default: 0
        }
    }
}
