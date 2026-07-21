public enum WordDiff {
    public enum Op: Equatable {
        case equal(String), delete(String), insert(String)
    }

    /// Lowercase; keep letters, digits, apostrophes; split on everything else.
    public static func normalize(_ text: String) -> [String] {
        var words: [String] = [], current = ""
        for ch in text.lowercased() {
            if ch.isLetter || ch.isNumber || ch == "'" { current.append(ch) }
            else if !current.isEmpty { words.append(current); current = "" }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    /// LCS word diff. Inputs capped at 1500 words (dictations are short; keeps DP bounded).
    public static func diff(_ rawA: [String], _ rawB: [String]) -> [Op] {
        let a = Array(rawA.prefix(1500)), b = Array(rawB.prefix(1500))
        let n = a.count, m = b.count
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var ops: [Op] = []; var i = 0, j = 0
        while i < n && j < m {
            if a[i] == b[j] { ops.append(.equal(a[i])); i += 1; j += 1 }
            else if lcs[i + 1][j] >= lcs[i][j + 1] { ops.append(.delete(a[i])); i += 1 }
            else { ops.append(.insert(b[j])); j += 1 }
        }
        while i < n { ops.append(.delete(a[i])); i += 1 }
        while j < m { ops.append(.insert(b[j])); j += 1 }
        return ops
    }
}
