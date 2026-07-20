import Foundation

public enum AliasSubstituter {
    /// Deterministic post-pass: alias -> canonical term, case-insensitive, whole words.
    /// Also normalizes casing when the canonical term itself was transcribed.
    /// Runs even when cleanup fell back to raw (spec §4).
    public static func apply(_ text: String, terms: [DictionaryTerm]) -> String {
        var result = text
        var pairs: [(alias: String, term: String)] = []
        for t in terms {
            pairs.append((t.term, t.term))            // canonical casing enforcement
            for a in t.aliases { pairs.append((a, t.term)) }
        }
        // longest alias first so overlapping aliases resolve sanely
        for (alias, term) in pairs.sorted(by: { $0.alias.count > $1.alias.count }) {
            let pattern = "(?i)\\b" + NSRegularExpression.escapedPattern(for: alias) + "\\b"
            result = result.replacingOccurrences(
                of: pattern,
                with: NSRegularExpression.escapedTemplate(for: term),
                options: .regularExpression)
        }
        return result
    }
}
