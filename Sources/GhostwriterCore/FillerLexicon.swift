public enum FillerLexicon {
    /// Single-word fillers. Note: the guardrail never removes anything itself —
    /// listing a word here only makes its DELETION free, so discourse markers
    /// like "so"/"yeah"/"basically" are safe to include.
    public static let words: Set<String> =
        ["um", "uh", "uhm", "umm", "erm", "er", "ah", "hmm", "mhm", "hm",
         "yeah", "so", "like", "basically"]
    /// Multi-word fillers, matched inside deleted spans only.
    public static let phrases: [String] = ["you know", "kind of", "sort of", "i mean"]
    public static func isFiller(_ word: String) -> Bool { words.contains(word) }
}
