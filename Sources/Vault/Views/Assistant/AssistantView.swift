import SwiftUI

/// The AI advisor screen.
///
/// Owns three concerns:
/// 1. **Chat history** via `ChatViewModel` (streaming responses, persistence,
///    `<think>` channel separation).
/// 2. **Voice input** via `SpeechRecognizer` (WhisperKit, French-pinned).
/// 3. **Presentation** of structured Markdown replies through `MarkdownText`.
///
/// The view warms up the Whisper model lazily in `.task`, so the user can
/// start typing as soon as the screen appears.
struct AssistantView: View {
    @EnvironmentObject private var store: Store
    @StateObject private var chat = ChatViewModel()
    @StateObject private var speech = SpeechRecognizer(modelName: "large-v3")

    @State private var showThinkingFor: UUID? = nil
    @State private var micLevel: Double = 0
    @State private var levelTimer: Timer? = nil
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Theme.stroke)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if chat.messages.isEmpty {
                            welcomeCard
                        }
                        ForEach(chat.messages) { msg in
                            MessageBubble(
                                message: msg,
                                isExpanded: showThinkingFor == msg.id,
                                onToggleThinking: {
                                    showThinkingFor = (showThinkingFor == msg.id) ? nil : msg.id
                                }
                            )
                            .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }
                .onChange(of: chat.messages.last?.content) { _, _ in
                    if let last = chat.messages.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: chat.messages.count) { _, _ in
                    if let last = chat.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider().background(Theme.stroke)
            composer
        }
        .background(Theme.canvas)
        .navigationTitle("Assistant")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    chat.reset()
                } label: {
                    Label("Nouvelle conversation", systemImage: "square.and.pencil")
                }
                .disabled(chat.messages.isEmpty)
            }
        }
        .task {
            // Précharge Whisper en arrière-plan (peut télécharger ~3 Go au 1er lancement)
            if !speech.modelReady {
                await speech.prepareModel()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.18)).frame(width: 36, height: 36)
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Conseiller Vault").font(.system(size: 14, weight: .semibold))
                Text(headerSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusChip
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var headerSubtitle: String {
        if chat.isStreaming { return "Réflexion en cours…" }
        switch speech.phase {
        case .downloadingModel: return "Chargement du modèle vocal…"
        case .recording:        return "Enregistrement…"
        case .transcribing:     return "Transcription…"
        case .error(let m):     return m
        default:                return "Deepseek-R1:14B local · Whisper large-v3"
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        if chat.isStreaming {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Stop").font(.system(size: 11))
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme.card, in: Capsule())
            .onTapGesture { chat.stop() }
        } else if speech.modelReady {
            Pill(text: "Voix prête", tint: Theme.positive)
        }
    }

    // MARK: - Welcome

    private var welcomeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                    Text("Pose une question sur ta situation").font(.system(size: 14, weight: .semibold))
                }
                Text("Je vois ton patrimoine, tes comptes, tes flux et tes récurrences. Je peux analyser, comparer aux ratios usuels et proposer des actions concrètes pour t'enrichir.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Divider().background(Theme.stroke)
                VStack(alignment: .leading, spacing: 6) {
                    suggestion("Analyse mon profil financier global.")
                    suggestion("Mon taux d'épargne est-il bon ? Comment l'améliorer ?")
                    suggestion("Quels sont mes 3 plus grosses fuites de cash ?")
                    suggestion("Donne-moi un plan d'action priorisé pour les 6 prochains mois.")
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func suggestion(_ text: String) -> some View {
        Button {
            chat.send(text, store: store)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.right.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
                Text(text).font(.system(size: 12))
                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 0) {
            if case .recording = speech.phase {
                recordingBar
            }
            HStack(alignment: .bottom, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    if chat.input.isEmpty {
                        Text("Pose ta question à ton conseiller…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                    }
                    TextEditor(text: $chat.input)
                        .scrollContentBackground(.hidden)
                        .font(.system(size: 13))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .frame(minHeight: 40, maxHeight: 110)
                        .focused($inputFocused)
                        .onSubmit { sendCurrent() }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10).stroke(Theme.stroke, lineWidth: 1)
                )

                micButton

                Button {
                    sendCurrent()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(canSend ? Theme.accent : Color.gray.opacity(0.5), in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSend)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private var canSend: Bool {
        !chat.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chat.isStreaming
    }

    private func sendCurrent() {
        chat.send(chat.input, store: store)
    }

    private var micButton: some View {
        let recording = speech.phase == .recording
        let transcribing = speech.phase == .transcribing
        let loading: Bool = {
            if case .downloadingModel = speech.phase { return true }
            return transcribing
        }()
        return Button {
            Task { await toggleMic() }
        } label: {
            ZStack {
                Circle()
                    .fill(recording ? Theme.negative : Theme.card)
                    .frame(width: 34, height: 34)
                if loading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(recording ? .white : Theme.accent)
                }
            }
            .overlay(Circle().stroke(Theme.stroke, lineWidth: recording ? 0 : 1))
        }
        .buttonStyle(.plain)
        .disabled(loading || chat.isStreaming)
        .help(recording ? "Arrêter l'enregistrement" : "Dicter ma question")
    }

    private var recordingBar: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.negative).frame(width: 8, height: 8)
                .opacity(0.4 + 0.6 * micLevel)
            Text("Enregistrement…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            // Mini meter
            HStack(spacing: 2) {
                ForEach(0..<14, id: \.self) { i in
                    let threshold = Double(i) / 14
                    Capsule()
                        .fill(micLevel >= threshold ? Theme.accent : Theme.stroke)
                        .frame(width: 3, height: 4 + CGFloat(i) * 1.2)
                }
            }
            Button("Annuler") {
                speech.cancel()
                stopLevelTimer()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(Theme.card)
    }

    private func toggleMic() async {
        switch speech.phase {
        case .recording:
            stopLevelTimer()
            do {
                let text = try await speech.stopAndTranscribe()
                if !text.isEmpty { chat.send(text, store: store) }
            } catch {
                // erreur déjà reflétée dans `speech.phase`
            }
        case .idle, .ready, .error:
            do {
                try await speech.startRecording()
                startLevelTimer()
            } catch {
                // erreur affichée via speech.phase
            }
        default:
            break
        }
    }

    private func startLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            Task { @MainActor in
                self.micLevel = self.speech.level()
            }
        }
    }
    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
        micLevel = 0
    }
}

// MARK: - Bubble

private struct MessageBubble: View {
    let message: ChatMessage
    let isExpanded: Bool
    let onToggleThinking: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user { Spacer(minLength: 60) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {

                if message.role == .assistant && !message.thinking.isEmpty {
                    thinkingBlock
                }

                bubbleContent

                if let err = message.error {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.negative)
                }
            }
            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        let isUser = message.role == .user
        let bg: Color = isUser ? Theme.accent.opacity(0.18) : Theme.card
        let textColor: Color = isUser ? .primary : .primary

        VStack(alignment: .leading, spacing: 6) {
            if message.content.isEmpty && message.isStreaming {
                HStack(spacing: 4) {
                    Circle().fill(.secondary).frame(width: 5, height: 5).opacity(0.3)
                    Circle().fill(.secondary).frame(width: 5, height: 5).opacity(0.6)
                    Circle().fill(.secondary).frame(width: 5, height: 5).opacity(0.9)
                }
                .padding(.vertical, 4)
            } else {
                MarkdownText(text: message.content)
                    .foregroundStyle(textColor)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isUser ? Color.clear : Theme.stroke, lineWidth: 1)
        )
    }

    private var thinkingBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onToggleThinking) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Image(systemName: "brain")
                        .font(.system(size: 11))
                    Text("Raisonnement").font(.system(size: 11, weight: .medium))
                    Text("(\(message.thinking.count) car.)").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(message.thinking)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.stroke, lineWidth: 1))
                    .textSelection(.enabled)
            }
        }
    }
}
