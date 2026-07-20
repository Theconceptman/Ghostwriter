import Testing
@testable import GhostwriterCore

@Suite struct WordDiffTests {
    @Test func normalizeStripsPunctuationAndCase() {
        #expect(WordDiff.normalize("Hello, World! It's 5 o'clock.")
            == ["hello", "world", "it's", "5", "o'clock"])
    }
    @Test func normalizeEmpty() {
        #expect(WordDiff.normalize("  ,. ") == [])
    }
    @Test func diffEqual() {
        #expect(WordDiff.diff(["a", "b"], ["a", "b"]) == [.equal("a"), .equal("b")])
    }
    @Test func diffDeletion() {
        #expect(WordDiff.diff(["um", "hello"], ["hello"]) == [.delete("um"), .equal("hello")])
    }
    @Test func diffInsertion() {
        #expect(WordDiff.diff(["hello"], ["oh", "hello"]) == [.insert("oh"), .equal("hello")])
    }
    @Test func diffSubstitutionIsDeletePlusInsert() {
        let ops = WordDiff.diff(["send", "tuesday"], ["send", "wednesday"])
        #expect(ops == [.equal("send"), .delete("tuesday"), .insert("wednesday")])
    }
}
