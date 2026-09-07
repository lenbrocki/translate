import Foundation
import Observation

/// User settings, persisted in `UserDefaults` (the API key excepted — that
/// goes to the keychain).
@Observable
@MainActor
final class Preferences {
    static let shared = Preferences()

    var sourceLanguage: String { didSet { defaults.set(sourceLanguage, forKey: Key.sourceLanguage) } }
    var targetLanguage: String { didSet { defaults.set(targetLanguage, forKey: Key.targetLanguage) } }
    var formality: Formality { didSet { defaults.set(formality.rawValue, forKey: Key.formality) } }
    var addresseeGender: Gender { didSet { defaults.set(addresseeGender.rawValue, forKey: Key.addresseeGender) } }
    var speakerGender: Gender { didSet { defaults.set(speakerGender.rawValue, forKey: Key.speakerGender) } }
    var effort: Effort { didSet { defaults.set(effort.rawValue, forKey: Key.effort) } }
    var autoCopy: Bool { didSet { defaults.set(autoCopy, forKey: Key.autoCopy) } }
    /// Which service translates. Each provider keeps its own key, so switching
    /// back and forth costs nothing.
    var provider: Provider { didSet { defaults.set(provider.rawValue, forKey: Key.provider) } }

    /// Changing this re-registers the global hot key; `AppCore` observes it.
    var shortcut: KeyCombo {
        didSet {
            guard let data = try? JSONEncoder().encode(shortcut) else { return }
            defaults.set(data, forKey: Key.shortcut)
        }
    }

    /// Bumped whenever the key changes, so views recompute `apiKey`.
    private var keyRevision = 0

    private let defaults = UserDefaults.standard

    private enum Key {
        static let sourceLanguage = "sourceLanguage"
        static let targetLanguage = "targetLanguage"
        static let formality = "formality"
        /// Still "gender": that key held the addressee's gender before the
        /// speaker got one of its own, and a saved choice should survive.
        static let addresseeGender = "gender"
        static let speakerGender = "speakerGender"
        static let effort = "effort"
        static let autoCopy = "autoCopy"
        static let provider = "provider"
        static let shortcut = "shortcut"
    }

    private init() {
        sourceLanguage = defaults.string(forKey: Key.sourceLanguage) ?? Languages.autoDetect
        targetLanguage = defaults.string(forKey: Key.targetLanguage) ?? "en"
        formality = defaults.string(forKey: Key.formality).flatMap(Formality.init) ?? .auto
        addresseeGender = defaults.string(forKey: Key.addresseeGender).flatMap(Gender.init) ?? .auto
        speakerGender = defaults.string(forKey: Key.speakerGender).flatMap(Gender.init) ?? .auto
        effort = defaults.string(forKey: Key.effort).flatMap(Effort.init) ?? .medium
        autoCopy = defaults.bool(forKey: Key.autoCopy)
        provider = defaults.string(forKey: Key.provider).flatMap(Provider.init) ?? .anthropic
        shortcut = defaults.data(forKey: Key.shortcut)
            .flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) } ?? .default
    }

    /// The register to actually translate with. A target language that has no
    /// formal/familiar distinction always translates as `.auto`, whatever the
    /// saved preference says.
    var effectiveFormality: Formality {
        Languages.marksFormality(targetLanguage) ? formality : .auto
    }

    /// The addressee gender to actually translate with, on the same terms: a
    /// target language that never inflects for it always translates as `.auto`.
    var effectiveAddresseeGender: Gender {
        Languages.marksAddresseeGender(targetLanguage) ? addresseeGender : .auto
    }

    /// And the speaker's. Gated separately because the two sets differ — Thai
    /// marks who is speaking but not who is spoken to.
    var effectiveSpeakerGender: Gender {
        Languages.marksSpeakerGender(targetLanguage) ? speakerGender : .auto
    }

    // MARK: - API keys

    /// The key for the selected provider, or nil if the user hasn't saved one.
    ///
    /// The keychain is the only source: a key inherited from the launching
    /// environment would apply or not depending on how the app was started,
    /// which is invisible from inside it. That includes the `.env` file in this
    /// project — it is there for the shell, not for the app.
    ///
    /// Read through once per provider and kept. Reading a keychain item's
    /// *data* is what prompts for permission when the item was written by a
    /// different build of the app, and this is read from a SwiftUI body, so a
    /// fresh read per access meant the prompt re-rendered the view that
    /// triggered it, on and on. One read per provider per launch, at first use.
    var apiKey: String? { apiKey(for: provider) }

    var hasAPIKey: Bool { apiKey != nil }

    func apiKey(for provider: Provider) -> String? {
        _ = keyRevision
        return loadedKey(for: provider)
    }

    func hasAPIKey(for provider: Provider) -> Bool { apiKey(for: provider) != nil }

    /// Last four characters, so the user can tell which key is loaded.
    func apiKeyHint(for provider: Provider) -> String {
        guard let key = apiKey(for: provider) else { return "" }
        return key.count > 4 ? "…" + String(key.suffix(4)) : "…"
    }

    func setAPIKey(_ key: String, for provider: Provider) {
        // Cache what we wrote rather than reading it straight back: the read
        // is the operation that prompts, and we already know the answer.
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let wrote = Keychain.writeAPIKey(trimmed, for: provider)
        cache(wrote ? (trimmed.isEmpty ? nil : trimmed) : Keychain.readAPIKey(for: provider), for: provider)
    }

    func clearAPIKey(for provider: Provider) {
        Keychain.deleteAPIKey(for: provider)
        cache(nil, for: provider)
    }

    /// Deliberately not observed: filling the cache during a view's body must
    /// not invalidate that view, or we are back to a loop. A provider whose key
    /// nobody has asked for is never read, so an unused provider never prompts.
    @ObservationIgnored private var cachedKeys: [Provider: String] = [:]
    @ObservationIgnored private var readProviders: Set<Provider> = []

    private func loadedKey(for provider: Provider) -> String? {
        if readProviders.insert(provider).inserted {
            cachedKeys[provider] = Keychain.readAPIKey(for: provider)
        }
        return cachedKeys[provider]
    }

    private func cache(_ key: String?, for provider: Provider) {
        cachedKeys[provider] = key
        readProviders.insert(provider)
        keyRevision += 1
    }
}
