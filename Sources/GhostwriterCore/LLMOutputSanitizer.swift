import Foundation

public enum LLMOutputSanitizer {
    /// Defense-in-depth for local models: strip reasoning blocks, wrapping quotes, extra blank lines.
    public static func sanitize(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "(?s)<think>.*?</think>", with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "(?s)<think>.*$", with: "", options: .regularExpression)
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.count >= 2, out.hasPrefix("\""), out.hasSuffix("\"") {
            out = String(out.dropFirst().dropLast())
        }
        out = out.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
