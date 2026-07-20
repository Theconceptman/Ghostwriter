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
        let config = WhisperKitConfig(model: modelName, download: true)
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
        options.chunkingStrategy = .vad
        if let contextPrompt, let tokenizer = pipe.tokenizer {
            // Prompt conditioning: the glossary becomes decoding context (spec §4).
            let tokens = tokenizer.encode(text: " " + contextPrompt)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            options.promptTokens = tokens
            options.usePrefillPrompt = true
        }
        let results = try await pipe.transcribe(audioArray: audio, decodeOptions: options)
        return results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
