import Foundation

/// Streams a translation from the Anthropic Messages API.
///
/// Claude Sonnet 5 with adaptive thinking; `effort` controls how much
/// deliberation it spends on the wording.
enum AnthropicClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"
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
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body(for: request))

        let (bytes, response) = try await session.bytes(for: urlRequest)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var raw = ""
            for try await line in bytes.lines { raw += line }
            throw TranslationError.api(
                StreamingHTTP.describe(status: http.statusCode, body: raw, vendor: Provider.anthropic.vendor)
            )
        }

        var header = HeaderParser(expectsHeader: request.detectsSource)

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let event = StreamingHTTP.event(from: line) else { continue }

            switch event["type"] as? String {
            // Only text blocks carry `text_delta`; thinking blocks emit
            // `thinking_delta`, which we deliberately ignore.
            case "content_block_delta":
                guard let delta = event["delta"] as? [String: Any],
                      delta["type"] as? String == "text_delta",
                      let text = delta["text"] as? String
                else { continue }
                header.feed(text).forEach(emit)

            // Errors mid-stream arrive as an SSE event, not an HTTP status.
            case "error":
                let detail = (event["error"] as? [String: Any]).flatMap(StreamingHTTP.message(fromError:))
                throw TranslationError.api(detail ?? "The translation stream failed.")

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
            "model": Provider.anthropic.model,
            "max_tokens": 32_000,
            "stream": true,
            "thinking": ["type": "adaptive"],
            "output_config": ["effort": request.effort.rawValue],
            "system": [[
                "type": "text",
                "text": TranslationPrompt.system(for: request),
                // The instructions are identical from one translation to the
                // next into the same language, so only the new text is billed
                // at full rate.
                "cache_control": ["type": "ephemeral"],
            ]],
            "messages": [[
                "role": "user",
                "content": TranslationPrompt.userMessage(for: request),
            ]],
        ]
    }
}
