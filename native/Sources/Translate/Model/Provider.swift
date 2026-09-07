import Foundation

/// Which service does the translating.
///
/// The two differ only in transport and in where their key is kept: the prompt,
/// the register and gender rules, and the detected-language header are the
/// same for both, so a translation can be compared across providers.
enum Provider: String, CaseIterable, Identifiable, Sendable {
    case anthropic
    case openai

    var id: String { rawValue }

    /// Short name for a segmented control.
    var label: String {
        switch self {
        case .anthropic: "Claude"
        case .openai: "OpenAI"
        }
    }

    /// The company whose key this is, for anything that talks about the key.
    var vendor: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openai: "OpenAI"
        }
    }

    var model: String {
        switch self {
        case .anthropic: "claude-sonnet-5"
        case .openai: "gpt-5.6-luna"
        }
    }

    var modelLabel: String {
        switch self {
        case .anthropic: "Claude Sonnet 5"
        case .openai: "GPT-5.6 Luna"
        }
    }

    /// Keychain account. Anthropic's is the name the app has always used, so a
    /// key saved by an earlier build is still found.
    var keychainAccount: String {
        switch self {
        case .anthropic: "anthropic-api-key"
        case .openai: "openai-api-key"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .anthropic: "sk-ant-…"
        case .openai: "sk-proj-…"
        }
    }
}
