import Foundation
import GhostwriterCore
import GhostwriterML
import WhisperKit

/// Micless end-to-end verification: pushes a WAV file through the exact
/// production pipeline (transcribe -> clean -> guardrail -> alias pass).
@main
struct Harness {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        guard let wavPath = args.first, !wavPath.hasPrefix("--") else {
            print("""
            usage: ghostwriter-harness <file.wav> [--mode lightTouch|verbatimTechnical|raw] \
            [--terms "A,B"] [--aliases "alias=Term;alias2=Term2"] [--no-clean]
            """)
            exit(2)
        }
        args.removeFirst()
        func flag(_ name: String) -> String? {
            guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        let mode = CleanupMode(rawValue: flag("--mode") ?? "lightTouch") ?? .lightTouch
        let noClean = args.contains("--no-clean")
        var terms: [DictionaryTerm] = (flag("--terms") ?? "").split(separator: ",")
            .map { DictionaryTerm(term: $0.trimmingCharacters(in: .whitespaces)) }
        for pair in (flag("--aliases") ?? "").split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            if let i = terms.firstIndex(where: { $0.term == kv[1] }) { terms[i].aliases.append(kv[0]) }
            else { terms.append(DictionaryTerm(term: kv[1], aliases: [kv[0]])) }
        }

        do {
            let audio = try await AudioProcessor.loadAudioAsFloatArray(fromPath: wavPath)
            print("Audio: \(wavPath)  (\(String(format: "%.1f", Double(audio.count) / 16000))s)")

            let transcriber = WhisperTranscriber()
            let t0 = Date()
            try await transcriber.preload { print("  [status] \($0)") }
            print("Model load: \(String(format: "%.2f", -t0.timeIntervalSinceNow))s")

            var cleaner: LlamaServerCleaner?
            if !noClean && mode != .raw {
                let c = LlamaServerCleaner()
                try await c.ensureRunning(readyTimeout: 1800) { print("  [status] \($0)") }
                cleaner = c
            }

            let pipeline = DictationPipeline(transcriber: transcriber, cleaner: cleaner)
            let t1 = Date()
            let result = await pipeline.process(audio: audio, mode: mode, dictionary: terms)
            let elapsed = -t1.timeIntervalSinceNow

            print("\nRAW:      \(result.rawText)")
            print("FINAL:    \(result.finalText)")
            print("FALLBACK: \(result.usedFallback)  MODE: \(result.mode.rawValue)")
            if let err = result.errorDescription { print("ERROR:    \(err)") }
            print("Pipeline time (warm): \(String(format: "%.2f", elapsed))s")
            cleaner?.shutdown()
            exit(result.errorDescription == nil ? 0 : 1)
        } catch {
            print("FAILED: \(error)"); exit(1)
        }
    }
}
