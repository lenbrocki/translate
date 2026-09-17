import AppKit
import Observation

/// One translation, as the UI sees it: the text streaming in, the detected
/// language, and whatever went wrong.
///
/// The main window and the overlay each own one, so dismissing the overlay
/// can't cancel work the main window is waiting on.
@Observable
@MainActor
final class TranslationSession {
    private(set) var output = ""
    private(set) var detectedLanguage: String?
    private(set) var errorMessage: String?
    private(set) var isStreaming = false
    /// The request being streamed, kept so the overlay can re-aim the same
    /// source text at a different language without capturing the selection again.
    private(set) var request: TranslationRequest?

    private var task: Task<Void, Never>?

    var isEmpty: Bool { output.isEmpty && errorMessage == nil }
    var trimmedOutput: String { output.trimmingCharacters(in: .whitespacesAndNewlines) }

    func start(_ request: TranslationRequest) {
        cancel()
        output = ""
        detectedLanguage = nil
        errorMessage = nil
        self.request = request

        guard let key = Preferences.shared.apiKey(for: request.provider) else {
            fail(TranslationError.missingKey(request.provider).localizedDescription)
            return
        }

        isStreaming = true
        let autoCopy = Preferences.shared.autoCopy

        task = Task { [weak self] in
            do {
                for try await chunk in Translator.stream(request, apiKey: key) {
                    guard let self, !Task.isCancelled else { return }
                    switch chunk {
                    case .language(let language): self.detectedLanguage = language
                    case .delta(let text): self.output += text
                    }
                }
                guard let self, !Task.isCancelled else { return }
                self.isStreaming = false
                self.output = self.trimmedOutput
                if autoCopy, !self.output.isEmpty { Clipboard.write(self.output) }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.fail(error.localizedDescription)
            }
        }
    }

    /// Surfaces a failure that happened before any streaming started (no
    /// selection, missing permission) the same way as an API error.
    func fail(_ message: String) {
        isStreaming = false
        errorMessage = message
    }

    func cancel() {
        task?.cancel()
        task = nil
        isStreaming = false
    }

    func reset() {
        cancel()
        output = ""
        detectedLanguage = nil
        errorMessage = nil
        request = nil
    }

    /// Everything needed to show this translation somewhere else.
    struct Snapshot {
        let request: TranslationRequest
        let output: String
        let detectedLanguage: String?
        let errorMessage: String?
        let isComplete: Bool
    }

    var snapshot: Snapshot? {
        request.map {
            Snapshot(
                request: $0,
                output: trimmedOutput,
                detectedLanguage: detectedLanguage,
                errorMessage: errorMessage,
                isComplete: !isStreaming
            )
        }
    }

    /// Takes over a translation from another session. A finished one is shown
    /// as it is, without asking the model again; one still streaming is
    /// started over, since its stream belongs to the session it came from.
    func restore(_ snapshot: Snapshot) {
        guard snapshot.isComplete else {
            start(snapshot.request)
            return
        }
        cancel()
        request = snapshot.request
        output = snapshot.output
        detectedLanguage = snapshot.detectedLanguage
        errorMessage = snapshot.errorMessage
    }
}

enum Clipboard {
    static func write(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
