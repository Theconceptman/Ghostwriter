import Testing
@testable import GhostwriterCore

@Suite struct AliasSubstituterTests {
    let terms = [
        DictionaryTerm(term: "Supabase", aliases: ["super base", "soup abase"]),
        DictionaryTerm(term: "Ghostwriter", aliases: ["ghost writer"]),
        DictionaryTerm(term: "GRDB", aliases: ["g r d b"]),
    ]
    @Test func multiWordAliasReplaced() {
        #expect(AliasSubstituter.apply("push it to super base now", terms: terms)
            == "push it to Supabase now")
    }
    @Test func caseInsensitiveMatch() {
        #expect(AliasSubstituter.apply("Ghost Writer is live", terms: terms)
            == "Ghostwriter is live")
    }
    @Test func noPartialWordMatch() {
        #expect(AliasSubstituter.apply("superbases are cool", terms: terms)
            == "superbases are cool")
    }
    @Test func canonicalSpellingEnforcedOnTermItself() {
        let t = [DictionaryTerm(term: "WhisperKit", aliases: [])]
        #expect(AliasSubstituter.apply("use whisperkit here", terms: t) == "use WhisperKit here")
    }
    @Test func emptyTerms() {
        #expect(AliasSubstituter.apply("hello", terms: []) == "hello")
    }
}
