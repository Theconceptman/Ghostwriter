import Foundation

public struct PipelineResult: Equatable {
    public let rawText: String
    public let finalText: String
    public let usedFallback: Bool
    public let mode: CleanupMode
    public let errorDescription: String?
}

struct TimeoutError: Error {}

func withTimeout<T: Sendable>(_ seconds: TimeInterval,
                              _ body: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await body() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

public final class DictationPipeline {
    private let transcriber: Transcriber
    private let cleaner: TextCleaner?
    private let cleanupTimeout: TimeInterval

    public init(transcriber: Transcriber, cleaner: TextCleaner?, cleanupTimeout: TimeInterval = 20) {
        self.transcriber = transcriber; self.cleaner = cleaner; self.cleanupTimeout = cleanupTimeout
    }

    public func process(audio: [Float], mode: CleanupMode, dictionary: [DictionaryTerm],
                        guardrailThreshold: Double = FidelityGuardrail.defaultThreshold) async -> PipelineResult {
        let glossary = dictionary.map(\.term)
        let contextPrompt = glossary.isEmpty ? nil : "Glossary: " + glossary.joined(separator: ", ") + "."

        let rawText: String
        do {
            rawText = try await transcriber.transcribe(audio: audio, contextPrompt: contextPrompt)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return PipelineResult(rawText: "", finalText: "", usedFallback: false, mode: mode,
                                  errorDescription: "Transcription failed: \(error)")
        }
        guard !rawText.isEmpty else {
            return PipelineResult(rawText: "", finalText: "", usedFallback: false, mode: mode,
                                  errorDescription: nil)
        }

        var finalText = rawText
        var usedFallback = false
        if mode != .raw, let cleaner {
            let system = CleanupPrompt.system(mode: mode, dictionaryTerms: glossary)
            let cleaned = try? await withTimeout(cleanupTimeout) { [cleaner] in
                try await cleaner.clean(transcript: rawText, systemPrompt: system)
            }
            if let cleaned {
                let sanitized = LLMOutputSanitizer.sanitize(cleaned)
                let verdict = FidelityGuardrail.evaluate(raw: rawText, cleaned: sanitized,
                                                         threshold: guardrailThreshold)
                if verdict.accepted && !sanitized.isEmpty { finalText = sanitized }
                else { usedFallback = true }
            } else { usedFallback = true }
        }
        finalText = AliasSubstituter.apply(finalText, terms: dictionary)
        return PipelineResult(rawText: rawText, finalText: finalText,
                              usedFallback: usedFallback, mode: mode, errorDescription: nil)
    }
}
