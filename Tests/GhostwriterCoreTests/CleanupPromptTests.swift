import Testing
@testable import GhostwriterCore

@Suite struct CleanupPromptTests {
    @Test func lightTouchForbidsRephrasing() {
        let p = CleanupPrompt.system(mode: .lightTouch, dictionaryTerms: [])
        #expect(p.contains("NEVER rephrase"))
    }
    @Test func technicalModeMentionsVerbatim() {
        let p = CleanupPrompt.system(mode: .verbatimTechnical, dictionaryTerms: [])
        #expect(p.contains("technical term"))
    }
    @Test func dictionaryTermsIncluded() {
        let p = CleanupPrompt.system(mode: .lightTouch, dictionaryTerms: ["Supabase", "GRDB"])
        #expect(p.contains("Supabase, GRDB"))
    }
    @Test func sanitizerStripsThinkBlocks() {
        #expect(LLMOutputSanitizer.sanitize("<think>hmm</think>\nFix the bug.") == "Fix the bug.")
    }
    @Test func sanitizerStripsUnterminatedThink() {
        #expect(LLMOutputSanitizer.sanitize("<think>rambling forever") == "")
    }
    @Test func sanitizerStripsWrappingQuotes() {
        #expect(LLMOutputSanitizer.sanitize("\"Fix the bug.\"") == "Fix the bug.")
    }
    @Test func sanitizerCollapsesBlankLines() {
        #expect(LLMOutputSanitizer.sanitize("a\n\n\n\nb") == "a\n\nb")
    }
}
