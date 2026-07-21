import Foundation

public struct GuardrailVerdict: Equatable {
    public let accepted: Bool
    public let penalty: Double
    public let allowance: Double
    public init(accepted: Bool, penalty: Double, allowance: Double) {
        self.accepted = accepted; self.penalty = penalty; self.allowance = allowance
    }
}

/// The anti-Wispr-Flow mechanism (spec §3): compares cleaned text against the
/// raw transcript and rejects cleanup that rewrote rather than trimmed. The
/// pipeline falls back to the raw transcript on rejection, so fidelity is a
/// property of the system, not of the model's obedience.
public enum FidelityGuardrail {
    public static let defaultThreshold = 0.15
    static let correctionMarkers = ["no wait", "i mean", "scratch that", "no actually",
                                    "wait no", "rather", "wait"]

    public static func evaluate(raw: String, cleaned: String,
                                threshold: Double = defaultThreshold) -> GuardrailVerdict {
        let r = WordDiff.normalize(raw), c = WordDiff.normalize(cleaned)
        if r.isEmpty { return GuardrailVerdict(accepted: true, penalty: 0, allowance: 0) }
        if c.isEmpty { return GuardrailVerdict(accepted: false, penalty: .infinity, allowance: 0) }

        var penalty = 0.0
        var span: [String] = []
        func flush() { if !span.isEmpty { penalty += deletionPenalty(span: span); span = [] } }
        for op in WordDiff.diff(r, c) {
            switch op {
            case .equal: flush()
            case .delete(let w): span.append(w)
            case .insert: flush(); penalty += 1.0   // added words are the cardinal sin
            }
        }
        flush()
        let allowance = max(threshold * Double(r.count), 1.5)
        return GuardrailVerdict(accepted: penalty <= allowance, penalty: penalty, allowance: allowance)
    }

    /// Deleted spans are where legitimate cleanup lives:
    /// fillers free, self-correction spans free, anything else 0.25/word.
    static func deletionPenalty(span: [String]) -> Double {
        let joined = span.joined(separator: " ")
        for marker in correctionMarkers where joined.contains(marker) { return 0 }
        var rest = span.filter { !FillerLexicon.isFiller($0) }.joined(separator: " ")
        for phrase in FillerLexicon.phrases { rest = rest.replacingOccurrences(of: phrase, with: "") }
        return Double(rest.split(separator: " ").count) * 0.25
    }
}
