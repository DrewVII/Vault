import Foundation
import SwiftUI

/// One message in the assistant conversation.
///
/// `thinking` stores the chain-of-thought emitted by reasoning models (Deepseek-R1
/// in particular) so the UI can show it in a separate collapsible panel.
/// `isStreaming` is transient and never persisted — see `ChatViewModel.persist()`.
struct ChatMessage: Identifiable, Codable, Hashable {
    enum Role: String, Codable { case user, assistant }
    var id: UUID = UUID()
    var role: Role
    var content: String
    var thinking: String = ""
    var isStreaming: Bool = false
    var error: String? = nil
    var createdAt: Date = .now
}

/// Coordinates the assistant chat: orchestrates streaming, persists the
/// conversation across launches and exposes observable state for the view.
///
/// Persistence lives next to the store in
/// `~/Library/Application Support/Vault/conversation.json`.
/// Writes are skipped while a response is streaming — we save the snapshot
/// once the LLM has finished or the user has cancelled.
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var input: String = ""
    @Published var isStreaming: Bool = false
    @Published var statusMessage: String? = nil

    private let llm: LLMClient
    private var currentTask: Task<Void, Never>?

    // MARK: - Persistance

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(llm: LLMClient = LLMClient()) {
        self.llm = llm

        let fm = FileManager.default
        let appSupport = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                       appropriateFor: nil, create: true))
            ?? fm.homeDirectoryForCurrentUser
        let dir = appSupport.appendingPathComponent("Vault", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("conversation.json")

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? decoder.decode([ChatMessage].self, from: data) else { return }
        // Au chargement : pas de message "en cours de streaming"
        self.messages = saved.map { msg in
            var m = msg
            m.isStreaming = false
            return m
        }
    }

    private func persist() {
        // Ne persiste pas pendant le streaming (économise les écritures disque)
        let snapshot = messages.map { msg -> ChatMessage in
            var m = msg
            m.isStreaming = false
            return m
        }
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Vault: échec d'écriture de la conversation : \(error)")
        }
    }

    // MARK: - Cycle de vie

    /// Vide la conversation (réinitialisation).
    func reset() {
        currentTask?.cancel()
        messages.removeAll()
        input = ""
        isStreaming = false
        statusMessage = nil
        persist()
    }

    func send(_ text: String, store: Store) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        let userMsg = ChatMessage(role: .user, content: trimmed)
        messages.append(userMsg)
        input = ""
        persist() // sauve immédiatement la question

        let assistantMsg = ChatMessage(role: .assistant, content: "", isStreaming: true)
        messages.append(assistantMsg)
        let assistantIndex = messages.count - 1

        isStreaming = true
        statusMessage = nil

        let context = FinancialContext.summary(for: store)
        let history = buildHistoryPayload(context: context)

        currentTask = Task { [weak self] in
            guard let self else { return }

            let ping = await llm.ping()
            if case .failure(let err) = ping {
                await MainActor.run {
                    self.messages[assistantIndex].error = err.errorDescription
                    self.messages[assistantIndex].isStreaming = false
                    self.isStreaming = false
                    self.persist()
                }
                return
            }

            do {
                for try await chunk in llm.stream(messages: history) {
                    if Task.isCancelled { break }
                    await MainActor.run {
                        switch chunk.channel {
                        case .thinking:
                            self.messages[assistantIndex].thinking.append(chunk.delta)
                        case .answer:
                            self.messages[assistantIndex].content.append(chunk.delta)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    let desc = (error as? LLMClient.LLMError)?.errorDescription ?? error.localizedDescription
                    self.messages[assistantIndex].error = desc
                }
            }

            await MainActor.run {
                self.messages[assistantIndex].isStreaming = false
                self.messages[assistantIndex].content = self.messages[assistantIndex].content
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                self.messages[assistantIndex].thinking = self.messages[assistantIndex].thinking
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                self.isStreaming = false
                self.persist()
            }
        }
    }

    func stop() {
        currentTask?.cancel()
        isStreaming = false
        if let last = messages.indices.last {
            messages[last].isStreaming = false
        }
        persist()
    }

    private func buildHistoryPayload(context: String) -> [LLMClient.Message] {
        var out: [LLMClient.Message] = []
        out.append(.init(role: "system", content: FinancialContext.systemPrompt))
        out.append(.init(role: "system", content: "Données à jour de l'utilisateur :\n\n\(context)"))
        for m in messages {
            if m.content.isEmpty && m.role == .assistant { continue }
            out.append(.init(role: m.role == .user ? "user" : "assistant", content: m.content))
        }
        return out
    }
}
