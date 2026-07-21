import Foundation
import GhostwriterCore
import WhisperKit

public final class WhisperTranscriber: Transcriber {
    public let modelName: String
    private var pipe: WhisperKit?

    public init(modelName: String = "large-v3-v20240930_turbo") { self.modelName = modelName }

    public var isLoaded: Bool { pipe != nil }
    public func unload() { pipe = nil }

    /// Loads the model, downloading on first run (WhisperKit caches the CoreML bundle locally).
    public func preload(status: ((String) -> Void)? = nil) async throws {
        guard pipe == nil else { return }
        status?("Loading speech model \(modelName)…")
        // load: true — without it WhisperKit defers model+tokenizer loading to the
        // first transcribe, which broke glossary injection (tokenizer nil) and hid
        // the real load cost inside the first user dictation.
        let config = WhisperKitConfig(model: modelName, load: true, download: true)
        pipe = try await WhisperKit(config)
        status?("Speech model ready.")
    }

    public func transcribe(audio: [Float], contextPrompt: String?) async throws -> String {
        try await preload()
        guard let pipe else {
            throw NSError(domain: "Ghostwriter", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Whisper model not loaded"])
        }
        var options = DecodingOptions()
        options.language = "en"
        options.temperature = 0
        options.skipSpecialTokens = true
        // No VAD chunking when prompt-conditioning: the combination produced
        // empty transcripts (verified 2026-07-20); dictation clips are short
        // enough that Whisper's native 30s windows handle them directly.
        options.chunkingStrategy = contextPrompt == nil ? .vad : nil
        // Whisper-level glossary biasing (options.promptTokens) is DISABLED:
        // WhisperKit 0.18's prompt path yields empty transcripts for this model —
        // immediate EOT with correctly encoded tokens, with and without timestamp
        // suppression (verified 2026-07-20). Dictionary accuracy is preserved by
        // the deterministic alias pass and the cleanup model's spelling reference
        // (spec §4 layers 2+3). Re-test on WhisperKit bumps via GW_EXPERIMENTAL_PROMPT=1.
        if let contextPrompt, let tokenizer = pipe.tokenizer,
           ProcessInfo.processInfo.environment["GW_EXPERIMENTAL_PROMPT"] != nil {
            let tokens = tokenizer.encode(text: " " + contextPrompt)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            options.promptTokens = tokens
            options.usePrefillPrompt = true
            options.withoutTimestamps = true
        }
        let results = try await pipe.transcribe(audioArray: audio, decodeOptions: options)
        return results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
