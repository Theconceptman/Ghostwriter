public enum CleanupPrompt {
    public static func system(mode: CleanupMode, dictionaryTerms: [String]) -> String {
        var p = """
        You clean up dictated speech transcripts. Apply ONLY these edits:
        - Remove filler words: um, uh, you know, I mean (when used as filler), kind of/sort of (when meaningless).
        - Fix punctuation, capitalization, and paragraph breaks.
        - When the speaker corrects themselves ("Tuesday, no wait, Wednesday"), keep only the corrected version.
        - Apply the exact spellings from the spelling reference below when the speaker says those terms.
        NEVER rephrase, summarize, expand, reorder, or "improve" wording.
        Never add words the speaker did not say (punctuation excepted).
        Preserve slang, grammar quirks, and sentence fragments exactly as spoken.
        Output ONLY the cleaned text - no commentary, no quotes around the result, no preamble.
        """
        if mode == .verbatimTechnical {
            p += """
            \nThis is technical dictation aimed at a programming tool. Keep every technical term, \
            file name, and code word verbatim. Do not expand abbreviations. Do not normalize \
            technical phrasing. When in doubt, leave it exactly as transcribed.
            """
        }
        if !dictionaryTerms.isEmpty {
            p += "\nSpelling reference: " + dictionaryTerms.joined(separator: ", ")
        }
        return p
    }
}
