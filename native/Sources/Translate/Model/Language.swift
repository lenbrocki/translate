import Foundation

/// A language the user can translate to or from.
///
/// `name` is the English name and is what actually goes into the prompt;
/// `native` is only ever shown in the picker.
struct Language: Identifiable, Hashable, Sendable {
    let code: String
    let name: String
    let native: String
    /// Whether the language grammaticalises a formal vs familiar level of
    /// address — Polish Pan/Pani vs ty, German Sie vs du. English doesn't, so
    /// asking for a register there is meaningless.
    let marksFormality: Bool
    /// Whether the gender of the person being addressed changes the wording —
    /// Polish "był Pan" vs "była Pani" and "zrobiłeś" vs "zrobiłaś", Hebrew and
    /// Arabic second-person verbs, Romance adjectives agreeing with "you".
    let marksAddresseeGender: Bool
    /// Whether the gender of the person speaking changes the wording — Polish
    /// "zrobiłem" vs "zrobiłam", Hebrew "אני הולך" vs "אני הולכת", Spanish
    /// "listo" vs "lista". Nearly the same set as `marksAddresseeGender`, but
    /// not identical: Thai marks the speaker (ครับ vs ค่ะ) and not the addressee.
    let marksSpeakerGender: Bool

    var id: String { code }

    /// Everything the search field should match against.
    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return name.localizedCaseInsensitiveContains(query)
            || native.localizedCaseInsensitiveContains(query)
            || code.localizedCaseInsensitiveContains(query)
    }
}

enum Languages {
    /// Sentinel used in place of a code when the source language is unknown.
    static let autoDetect = "auto"

    static let all: [Language] = [
        Language(code: "ar", name: "Arabic", native: "العربية", marksFormality: false, marksAddresseeGender: true, marksSpeakerGender: true),
        Language(code: "bg", name: "Bulgarian", native: "Български", marksFormality: true, marksAddresseeGender: true, marksSpeakerGender: true),
        Language(code: "cs", name: "Czech", native: "Čeština", marksFormality: true, marksAddresseeGender: true, marksSpeakerGender: true),
        Language(code: "da", name: "Danish", native: "Dansk", marksFormality: false, marksAddresseeGender: false, marksSpeakerGender: false),
        Language(code: "de", name: "German", native: "Deutsch", marksFormality: true, marksAddresseeGender: true, marksSpeakerGender: true),
        Language(code: "el", name: "Greek", native: "Ελληνικά", marksFormality: true, marksAddresseeGender: true, marksSpeakerGender: true),
        Language(code: "en", name: "English", native: "English", marksFormality: false, marksAddresseeGender: false, marksSpeakerGender: false),
        Language(code: "en-GB", name: "British English", native: "English (UK)", marksFormality: false, marksAddresseeGender: false, marksSpeakerGender: false),
        Language(code: "en-US", name: "American English", native: "English (US)", marksFormality: false, marksAddresseeGender: false, marksSpeakerGender: false),
        Language(code: "es", name: "Spanish", native: "Español", marksFormality: true, marksAddresseeGender: true, marksSpeakerGender: true),
        Language(code: "et", name: "Estonian", native: "Eesti", marksFormality: true, marksAddresseeGender: false, marksSpeakerGender: false),
        Language(code: "fi", name: "Finnish", native: "Suomi", marksFormality: true, marksAddresseeGender: false, marksSpeakerGender: false),
        Language(code: "fr", name: "French", native: "Français", marksFormality: true, marksAddresseeGender: true, marksSpeakerGender: true),
        Language(code: "he", name: "Hebrew", native: "עברית", marksFormality: false, marksAddresseeGender: true, marksSpeakerGender: true),
        Language(code: "hi", name: "Hindi", native: "हिन्दी", marksFormality: true, marksAddresseeGender: true, marksSpeakerGender: true),
        Language(code: "hu", name: "Hungarian", native: "Magyar", marksFormality: true, marksAddresseeGender: false, marksSpeakerGender: false),
        Language(code: "id", name: "Indonesian", native: "Bahasa Indonesia", marksFormality: true, marksAddresseeGender: false, marksSpeakerGender: false),
        Language(code: "it", name: "Italian", native: "Italiano", marksFormality: true, marksAddresseeGender: true, marksSpeakerGender: true),
        Language(code: "ja", name: "Japanese", native: "日本語", marksFormality: true, marksAddresseeGender: false, marksSpeakerGender: false),
        Language(code: "ko", name: "Korean", native: "한국어", marksFormality: true, marksAddresseeGender: false, marksSpeakerGender: false),
        Language(code: "lt", name: "Lithuanian", native: "Lietuvių", marksFormality: true, marksAddresseeGender: true, marksSpeakerGender: true),
        Language(code: "lv", name: "Latvian", native: "Latviešu", marksFormality: true, marksAddresseeGender: true, marksSpeakerGender: true),
        Language(code: "nb", name: "Norwegian Bokmål", native: "Norsk bokmål", marksFormality: false, marksAddresseeGender: false, marksSpeakerGender: false),
        Language(code: "nl", name: "Dutch", native: "Nederlands", marksFormality: true, marksAddresseeGender: false, marksSpeakerGender: false),
        Language(code: "pl", name: "Polish", native: "Polski", marksFormality: true, marksAddresseeGender: true, marksSpeakerGender: true),
        Language(code: "pt-BR", name: "Brazilian Portuguese", native: "Português (BR)", marksFormality: true, marksAddresseeGender: true, marksSpeakerGender: true),
        Language(code: "pt-PT", name: "European Portuguese", native: "Português (PT)", marksFormality: true, marksAddresseeGender: true, marksSpeakerGender: true),
        Language(code: "ro", name: "Romanian", native: "Română", marksFormality: true, marksAddresseeGender: true, marksSpeakerGender: true),
        Language(code: "ru", name: "Russian", native: "Русский", marksFormality: true, marksAddresseeGender: true, marksSpeakerGender: true),
        Language(code: "sk", name: "Slovak", native: "Slovenčina", marksFormality: true, marksAddresseeGender: true, marksSpeakerGender: true),
        Language(code: "sl", name: "Slovenian", native: "Slovenščina", marksFormality: true, marksAddresseeGender: true, marksSpeakerGender: true),
        Language(code: "sv", name: "Swedish", native: "Svenska", marksFormality: false, marksAddresseeGender: false, marksSpeakerGender: false),
        Language(code: "th", name: "Thai", native: "ไทย", marksFormality: true, marksAddresseeGender: false, marksSpeakerGender: true),
        Language(code: "tr", name: "Turkish", native: "Türkçe", marksFormality: true, marksAddresseeGender: false, marksSpeakerGender: false),
        Language(code: "uk", name: "Ukrainian", native: "Українська", marksFormality: true, marksAddresseeGender: true, marksSpeakerGender: true),
        Language(code: "vi", name: "Vietnamese", native: "Tiếng Việt", marksFormality: true, marksAddresseeGender: true, marksSpeakerGender: true),
        Language(code: "zh-Hans", name: "Simplified Chinese", native: "简体中文", marksFormality: true, marksAddresseeGender: false, marksSpeakerGender: false),
        Language(code: "zh-Hant", name: "Traditional Chinese", native: "繁體中文", marksFormality: true, marksAddresseeGender: false, marksSpeakerGender: false),
    ]

    /// English name for a code. Unknown codes pass through unchanged so a
    /// hand-edited preference still does something sensible.
    static func name(for code: String) -> String {
        all.first { $0.code == code }?.name ?? code
    }

    /// Whether picking a register makes sense for this target language.
    /// Unknown codes get the benefit of the doubt.
    static func marksFormality(_ code: String) -> Bool {
        all.first { $0.code == code }?.marksFormality ?? true
    }

    /// Whether the addressee's gender can change the translation.
    /// Unknown codes get the benefit of the doubt.
    static func marksAddresseeGender(_ code: String) -> Bool {
        all.first { $0.code == code }?.marksAddresseeGender ?? true
    }

    /// Same question for the speaker — the "I" of the text.
    static func marksSpeakerGender(_ code: String) -> Bool {
        all.first { $0.code == code }?.marksSpeakerGender ?? true
    }

    /// Label for the toolbar pickers.
    static func label(for code: String) -> String {
        code == autoDetect ? "Detect language" : name(for: code)
    }
}

/// Level of address to use in the translation.
enum Formality: String, CaseIterable, Identifiable, Sendable {
    case auto, informal, formal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "Auto"
        case .informal: "Informal"
        case .formal: "Formal"
        }
    }
}

/// A person's gender, for the languages that inflect for it. Asked twice: once
/// for the speaker — the "I" of the text — and once for the addressee, since a
/// message can easily be from a woman to a man or the other way round.
enum Gender: String, CaseIterable, Identifiable, Sendable {
    case auto, male, female

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "Auto"
        case .male: "Male"
        case .female: "Female"
        }
    }
}

/// How much deliberation Claude spends on the wording — maps straight to
/// `output_config.effort` on the Messages API.
enum Effort: String, CaseIterable, Identifiable, Sendable {
    case low, medium, high, xhigh

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "Very high"
        }
    }
}
