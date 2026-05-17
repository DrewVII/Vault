import Foundation

/// Streaming chat client for an [Ollama](https://ollama.com) server.
///
/// The client speaks Ollama's `/api/chat` protocol and yields tokens as they
/// arrive. It also understands the **reasoning channel** used by Deepseek-R1
/// (and similar reasoning models), which interleaves chain-of-thought inside
/// `<think>…</think>` tags within the same content stream.
///
/// Output is exposed as an `AsyncThrowingStream<Chunk, Error>` of typed
/// deltas — each delta is tagged either `.thinking` or `.answer`, so the UI
/// can render them in separate surfaces (a collapsed reasoning panel vs. the
/// final bubble).
struct LLMClient {

    // MARK: - Types

    /// One message in the chat history sent to Ollama.
    struct Message: Codable {
        /// `"system"`, `"user"` or `"assistant"`.
        let role: String
        let content: String
    }

    /// A typed slice of the streamed response.
    struct Chunk {
        enum Channel { case thinking, answer }
        let channel: Channel
        let delta: String
    }

    enum LLMError: Error, LocalizedError {
        case badResponse(Int)
        case ollamaUnreachable
        case modelMissing(String)

        var errorDescription: String? {
            switch self {
            case .badResponse(let code):
                return "Ollama returned status \(code)."
            case .ollamaUnreachable:
                return "Ollama is unreachable on localhost:11434. Start it with `ollama serve`."
            case .modelMissing(let m):
                return "Model '\(m)' not found locally. Run: ollama pull \(m)"
            }
        }
    }

    // MARK: - Configuration

    let endpoint: URL
    let model: String

    /// - Parameters:
    ///   - model: Ollama model tag (e.g. `"deepseek-r1:14b"`).
    ///   - endpoint: Chat endpoint of an Ollama-compatible server.
    init(model: String = "deepseek-r1:14b",
         endpoint: URL = URL(string: "http://localhost:11434/api/chat")!) {
        self.endpoint = endpoint
        self.model = model
    }

    // MARK: - Health-check

    /// Verifies the server is reachable **and** the configured model is
    /// available locally, returning a precise diagnostic otherwise.
    func ping() async -> Result<Void, LLMError> {
        var req = URLRequest(url: URL(string: "http://localhost:11434/api/tags")!)
        req.timeoutInterval = 3
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                return .failure(.ollamaUnreachable)
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                let names = models.compactMap { $0["name"] as? String }
                if !names.contains(where: { $0.hasPrefix(model) }) {
                    return .failure(.modelMissing(model))
                }
            }
            return .success(())
        } catch {
            return .failure(.ollamaUnreachable)
        }
    }

    // MARK: - Streaming chat

    /// Sends a chat completion request and streams the response.
    ///
    /// The returned `AsyncThrowingStream`:
    /// - yields one `Chunk` per safely-emittable slice of content,
    /// - tags chunks `.thinking` or `.answer` based on the active `<think>` state,
    /// - finishes cleanly when Ollama sends `done: true`,
    /// - cancels the underlying HTTP task if the consumer terminates iteration.
    func stream(messages: [Message]) -> AsyncThrowingStream<Chunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // -- Build the request ----------------------------------
                    var req = URLRequest(url: endpoint)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.timeoutInterval = 600  // generation can be slow on 14B models

                    let body: [String: Any] = [
                        "model": model,
                        "messages": messages.map { ["role": $0.role, "content": $0.content] },
                        "stream": true,
                        "options": [
                            "temperature": 0.4,
                            "num_ctx": 8192
                        ]
                    ]
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        throw LLMError.badResponse(http.statusCode)
                    }

                    // -- Parse the JSONL stream -----------------------------
                    //
                    // Ollama emits one JSON object per line:
                    //   {"message":{"role":"assistant","content":"…"},"done":false}
                    // We accumulate the content into `buffer`, then strip out
                    // `<think>` / `</think>` markers, yielding the in-between
                    // text on the appropriate channel.
                    var insideThink = false
                    var buffer = ""

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard !line.isEmpty,
                              let data = line.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }

                        if obj["error"] is String {
                            throw LLMError.badResponse(500)
                        }

                        guard let msg = obj["message"] as? [String: Any],
                              let content = msg["content"] as? String,
                              !content.isEmpty else {
                            if let done = obj["done"] as? Bool, done { break }
                            continue
                        }

                        buffer.append(content)

                        // -- State machine over <think> / </think> -----------
                        //
                        // The trick is that a tag can be **split across two
                        // chunks** (e.g. one chunk ends with "</thi", the next
                        // starts with "nk>"). We therefore keep a small tail
                        // of the buffer un-emitted whenever it could be the
                        // start of the awaited token.
                        while !buffer.isEmpty {
                            let token = insideThink ? "</think>" : "<think>"
                            if let range = buffer.range(of: token) {
                                // Found a complete tag — emit everything
                                // before it and flip the channel state.
                                let prefix = String(buffer[..<range.lowerBound])
                                if !prefix.isEmpty {
                                    continuation.yield(Chunk(
                                        channel: insideThink ? .thinking : .answer,
                                        delta: prefix
                                    ))
                                }
                                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                                insideThink.toggle()
                            } else {
                                // No full tag yet. Emit the "stable" prefix —
                                // everything that **cannot** be the start of
                                // the awaited token — and keep the rest for
                                // the next iteration.
                                let safeTail = bufferSafeTailLength(in: buffer, awaitedToken: token)
                                let stable = String(buffer.prefix(buffer.count - safeTail))
                                if !stable.isEmpty {
                                    continuation.yield(Chunk(
                                        channel: insideThink ? .thinking : .answer,
                                        delta: stable
                                    ))
                                    buffer.removeFirst(stable.count)
                                }
                                break
                            }
                        }
                    }

                    // Flush whatever is left in the buffer (no trailing tag).
                    if !buffer.isEmpty {
                        continuation.yield(Chunk(
                            channel: insideThink ? .thinking : .answer,
                            delta: buffer
                        ))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    /// How many trailing characters of the buffer **could** be the prefix of
    /// the awaited token (`<think>` or `</think>`), and must therefore be
    /// withheld from emission until more data arrives.
    ///
    /// Example:
    ///   buffer = "Hello </thi", awaitedToken = "</think>"
    ///   ⇒ returns 5 (the "</thi" tail is a prefix of "</think>")
    private func bufferSafeTailLength(in buffer: String, awaitedToken token: String) -> Int {
        let maxCheck = min(buffer.count, token.count - 1)
        for n in stride(from: maxCheck, through: 1, by: -1) {
            let suffix = buffer.suffix(n)
            if token.hasPrefix(String(suffix)) { return n }
        }
        return 0
    }
}
