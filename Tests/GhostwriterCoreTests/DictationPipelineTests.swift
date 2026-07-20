import Foundation
import Testing
@testable import GhostwriterCore

final class FakeTranscriber: Transcriber {
    var result: Result<String, Error> = .success("")
    var receivedPrompt: String?
    func transcribe(audio: [Float], contextPrompt: String?) async throws -> String {
        receivedPrompt = contextPrompt
        return try result.get()
    }
}
final class FakeCleaner: TextCleaner {
    var result: Result<String, Error> = .success("")
    var delay: TimeInterval = 0
    func clean(transcript: String, systemPrompt: String) async throws -> String {
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1e9)) }
        return try result.get()
    }
}
struct FakeError: Error {}

@Suite struct DictationPipelineTests {
    let terms = [DictionaryTerm(term: "Supabase", aliases: ["super base"])]

    @Test func happyPathUsesCleanedText() async {
        let t = FakeTranscriber(); t.result = .success("um push it to super base")
        let c = FakeCleaner(); c.result = .success("Push it to super base.")
        let r = await DictationPipeline(transcriber: t, cleaner: c)
            .process(audio: [0], mode: .lightTouch, dictionary: terms)
        #expect(r.finalText == "Push it to Supabase.")   // alias pass runs after cleanup
        #expect(!r.usedFallback)
        #expect(t.receivedPrompt == "Glossary: Supabase.")
    }
    @Test func overreachFallsBackToRawWithAliasPass() async {
        let t = FakeTranscriber(); t.result = .success("make the login page way faster please it is slow")
        let c = FakeCleaner(); c.result = .success("Optimize authentication latency for improved UX.")
        let r = await DictationPipeline(transcriber: t, cleaner: c)
            .process(audio: [0], mode: .lightTouch, dictionary: [])
        #expect(r.usedFallback)
        #expect(r.finalText == "make the login page way faster please it is slow")
    }
    @Test func cleanerErrorFallsBackToRaw() async {
        let t = FakeTranscriber(); t.result = .success("hello world")
        let c = FakeCleaner(); c.result = .failure(FakeError())
        let r = await DictationPipeline(transcriber: t, cleaner: c)
            .process(audio: [0], mode: .lightTouch, dictionary: [])
        #expect(r.usedFallback)
        #expect(r.finalText == "hello world")
    }
    @Test func cleanerTimeoutFallsBackToRaw() async {
        let t = FakeTranscriber(); t.result = .success("hello world")
        let c = FakeCleaner(); c.result = .success("Hello world."); c.delay = 5
        let p = DictationPipeline(transcriber: t, cleaner: c, cleanupTimeout: 0.05)
        let r = await p.process(audio: [0], mode: .lightTouch, dictionary: [])
        #expect(r.usedFallback)
        #expect(r.finalText == "hello world")
    }
    @Test func rawModeSkipsCleaner() async {
        let t = FakeTranscriber(); t.result = .success("um hello")
        let c = FakeCleaner(); c.result = .failure(FakeError())   // would explode if called
        let r = await DictationPipeline(transcriber: t, cleaner: c)
            .process(audio: [0], mode: .raw, dictionary: [])
        #expect(r.finalText == "um hello")
        #expect(!r.usedFallback)
    }
    @Test func nilCleanerActsAsRaw() async {
        let t = FakeTranscriber(); t.result = .success("um hello")
        let r = await DictationPipeline(transcriber: t, cleaner: nil)
            .process(audio: [0], mode: .lightTouch, dictionary: [])
        #expect(r.finalText == "um hello")
    }
    @Test func transcriberErrorReported() async {
        let t = FakeTranscriber(); t.result = .failure(FakeError())
        let r = await DictationPipeline(transcriber: t, cleaner: nil)
            .process(audio: [0], mode: .lightTouch, dictionary: [])
        #expect(r.errorDescription != nil)
        #expect(r.finalText == "")
    }
    @Test func emptyTranscriptShortCircuits() async {
        let t = FakeTranscriber(); t.result = .success("   ")
        let r = await DictationPipeline(transcriber: t, cleaner: nil)
            .process(audio: [0], mode: .lightTouch, dictionary: [])
        #expect(r.finalText == "")
        #expect(r.errorDescription == nil)
    }
    @Test func thinkBlocksSanitizedBeforeGuardrail() async {
        let t = FakeTranscriber(); t.result = .success("fix the bug now")
        let c = FakeCleaner(); c.result = .success("<think>user wants...</think>Fix the bug now.")
        let r = await DictationPipeline(transcriber: t, cleaner: c)
            .process(audio: [0], mode: .lightTouch, dictionary: [])
        #expect(r.finalText == "Fix the bug now.")
        #expect(!r.usedFallback)
    }
}
