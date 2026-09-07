import Foundation

/// Streams a translation from the OpenAI Responses API.
///
/// GPT-5.6 Luna, whose `reasoning.effort` is the same dial as Claude's
/// `output_config.effort` — the app's four Quality levels are valid values for
/// both, so the setting means the same thing whichever provider is selected.
enum OpenAIClient {
    private static let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    private static let session = StreamingHTTP.session()

    static func stream(_ request: TranslationRequest, apiKey: String) -> AsyncThrowingStream<TranslationChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(request, apiKey: apiKey) { continuation.yield($0) }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func run(
        _ request: TranslationRequest,
        apiKey: String,
        emit: (TranslationChunk) -> Void
    ) async throws {
        guard request.text.count <= Translator.maxInputCharacters else {
            throw TranslationError.tooLong(limit: Translator.maxInputCharacters)
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body(for: request))

        let (bytes, response) = try await session.bytes(for: urlRequest)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var raw = ""
            for try await line in bytes.lines { raw += line }
            throw TranslationError.api(
                StreamingHTTP.describe(status: http.statusCode, body: raw, vendor: Provider.openai.vendor)
            )
        }

        var header = HeaderParser(expectsHeader: request.detectsSource)

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let event = StreamingHTTP.event(from: line) else { continue }

            switch event["type"] as? String {
            // Reasoning arrives as its own item type and is never forwarded;
            // only the visible answer streams through `output_text`.
            case "response.output_text.delta":
                guard let text = event["delta"] as? String else { continue }
                header.feed(text).forEach(emit)

            // A failure after the 200 comes back as an event on the stream.
            case "error", "response.failed", "response.incomplete":
                throw TranslationError.api(failure(in: event))

            default:
                continue
            }
        }

        header.finish().forEach(emit)
    }

    /// Internal rather than private so a harness can assert the wire shape
    /// without making a paid request.
    static func body(for request: TranslationRequest) -> [String: Any] {
        [
            "model": Provider.openai.model,
            "instructions": TranslationPrompt.system(for: request),
            "input": [[
                "role": "user",
                "content": TranslationPrompt.userMessage(for: request),
            ]],
            "max_output_tokens": 32_000,
            "stream": true,
            "reasoning": ["effort": request.effort.rawValue],
            // Nothing here needs to be retrievable later, and a translation is
            // often the most private thing the user has on screen.
            "store": false,
        ]
    }

    /// Pulls a message out of whichever shape the failure arrived in: a bare
    /// `error` event, or a terminal response object carrying `error` or
    /// `incomplete_details`.
    private static func failure(in event: [String: Any]) -> String {
        if let error = event["error"] as? [String: Any],
           let message = StreamingHTTP.message(fromError: error) {
            return message
        }
        if let response = event["response"] as? [String: Any] {
            if let error = response["error"] as? [String: Any],
               let message = StreamingHTTP.message(fromError: error) {
                return message
            }
            if let reason = (response["incomplete_details"] as? [String: Any])?["reason"] as? String {
                return "The translation stopped early (\(reason))."
            }
        }
        if let message = event["message"] as? String { return message }
        return "The translation stream failed."
    }
}
