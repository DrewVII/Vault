import Foundation
import AVFoundation
import WhisperKit

/// On-device speech-to-text powered by [WhisperKit](https://github.com/argmaxinc/WhisperKit).
///
/// Records 16 kHz mono PCM from the system microphone, then transcribes the
/// file with a Whisper model running on the Apple Neural Engine via CoreML.
/// Nothing leaves the machine — the only network access happens once, when the
/// model weights are downloaded from Hugging Face on first launch.
///
/// The language is **pinned** to French via `DecodingOptions(language: "fr")`
/// to prevent WhisperKit from auto-detecting English on short utterances and
/// silently translating the transcript.
@MainActor
final class SpeechRecognizer: ObservableObject {

    /// High-level state used to drive the UI (header label, mic button glyph,
    /// recording bar, error toasts).
    enum Phase: Equatable {
        case idle
        case downloadingModel(progress: Double)
        case ready
        case recording
        case transcribing
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var modelReady: Bool = false

    private var whisperKit: WhisperKit?
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    /// Whisper model identifier. `"large-v3"` ≈ 3 GB on first download,
    /// `"base"` ≈ 150 MB. The full mapping is defined by WhisperKit.
    let modelName: String

    init(modelName: String = "large-v3") {
        self.modelName = modelName
    }

    // MARK: - Model preparation

    /// Loads (or downloads, on first launch) the Whisper model.
    /// Safe to call multiple times — subsequent calls are no-ops.
    /// Recommended: call from an `.task { … }` modifier on the assistant view
    /// so the user can start typing while the model warms up.
    func prepareModel() async {
        guard whisperKit == nil else { return }
        phase = .downloadingModel(progress: 0)
        do {
            let config = WhisperKitConfig(
                model: modelName,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: true
            )
            self.whisperKit = try await WhisperKit(config)
            self.modelReady = true
            self.phase = .ready
        } catch {
            self.phase = .error("Whisper model unavailable: \(error.localizedDescription)")
        }
    }

    // MARK: - Permissions

    /// Triggers the system microphone permission prompt if needed and returns
    /// whether access was granted.
    func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                cont.resume(returning: granted)
            }
        }
    }

    // MARK: - Recording

    /// Starts a new recording into a temp WAV file. The format (16 kHz mono
    /// PCM, 16-bit little-endian) matches what Whisper expects natively.
    func startRecording() async throws {
        guard recorder == nil else { return }

        let granted = await requestMicrophoneAccess()
        guard granted else {
            phase = .error("Microphone access denied.")
            throw NSError(domain: "Vault.Speech", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Microphone access denied"])
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-mic-\(UUID().uuidString).wav")

        // Whisper expects 16 kHz mono PCM — record directly in that format to
        // skip any conversion step before transcription.
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.isMeteringEnabled = true
        guard rec.prepareToRecord(), rec.record() else {
            throw NSError(domain: "Vault.Speech", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not start recording"])
        }

        self.recorder = rec
        self.recordingURL = url
        self.phase = .recording
    }

    /// Stops the current recording, transcribes the audio with the Whisper
    /// model, deletes the temp file and returns the resulting French text.
    func stopAndTranscribe() async throws -> String {
        guard let rec = recorder, let url = recordingURL else { return "" }
        rec.stop()
        recorder = nil
        recordingURL = nil

        // The user may have hit the mic button before the model finished
        // downloading — block here just in case.
        if whisperKit == nil { await prepareModel() }
        guard let kit = whisperKit else {
            phase = .error("Whisper is not initialised")
            throw NSError(domain: "Vault.Speech", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Whisper not initialised"])
        }

        phase = .transcribing
        do {
            // Pin the language to French and force the **transcription** task
            // (as opposed to the .translate task, which would convert to
            // English). Disabling auto-detection avoids the common pitfall
            // where short French utterances are detected as English.
            let options = DecodingOptions(
                verbose: false,
                task: .transcribe,
                language: "fr",
                temperature: 0.0,
                temperatureFallbackCount: 3,
                sampleLength: 224,
                usePrefillPrompt: true,
                usePrefillCache: true,
                detectLanguage: false,
                skipSpecialTokens: true,
                withoutTimestamps: true,
                suppressBlank: true,
                chunkingStrategy: .vad
            )
            let results = try await kit.transcribe(audioPath: url.path, decodeOptions: options)
            try? FileManager.default.removeItem(at: url)
            phase = .ready
            return results.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            try? FileManager.default.removeItem(at: url)
            phase = .error("Transcription failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Abort a recording in progress without running transcription.
    func cancel() {
        recorder?.stop()
        if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
        recorder = nil
        recordingURL = nil
        if case .recording = phase { phase = .ready }
    }

    /// Current normalised audio level (0…1) for the recording-bar meter.
    /// Powered by AVFoundation's `averagePower(forChannel:)` mapped from dB.
    func level() -> Double {
        guard let rec = recorder else { return 0 }
        rec.updateMeters()
        let db = rec.averagePower(forChannel: 0)
        // −60 dB → 0, 0 dB → 1 (rough psycho-acoustic mapping)
        let normalized = pow(10, Double(db) / 20)
        return min(max(normalized, 0), 1)
    }
}
