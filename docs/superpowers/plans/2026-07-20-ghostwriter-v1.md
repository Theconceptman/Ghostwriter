# Ghostwriter v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS menu-bar dictation app — hold Fn, speak, release, cleaned text appears at the cursor — fully local, $0 running cost, with a fidelity guardrail that makes rewriting the user's words impossible.

**Architecture:** SwiftPM package (no Xcode project; machine has Command Line Tools only). Pure-logic core library (`GhostwriterCore`, fully unit-tested), an ML wrapper library (`GhostwriterML`: WhisperKit for STT, a managed `llama-server` subprocess for cleanup), an AppKit/SwiftUI app target, and a CLI harness that runs the exact production pipeline on WAV files for micless end-to-end verification.

**Tech Stack:** Swift 5 mode (tools 5.10) on Swift 6.2.3 · WhisperKit (Whisper large-v3-turbo, CoreML/ANE) · llama.cpp via Homebrew (`llama-server`, Qwen3-4B-Instruct-2507 GGUF Q4_K_M) · GRDB/SQLite with FTS5 · AppKit + SwiftUI · `say`/`afconvert` for synthetic test audio.

## Global Constraints

- **$0 running cost.** No API calls, no subscriptions; network use limited to one-time model downloads. (Spec §Hard constraints)
- **Voice fidelity.** Cleanup can never substantially rewrite the user's words; guardrail default threshold **0.15**, fallback to raw on breach. (Spec §3)
- **Privacy.** Audio and transcripts never leave the machine. (Spec §Hard constraints)
- **Performance.** Release-to-text ≤ 1s for ≤10s utterances (warm models); first syllable never clipped; idle RAM ≤ 150 MB with models unloaded. (Spec §7)
- **Platform.** macOS 15+ (`platforms: [.macOS(.v15)]`), Apple Silicon. Build must succeed with Command Line Tools only — no `xcodebuild`, no `.xcodeproj`.
- **Spec amendment (2026-07-20):** cleanup engine is llama.cpp/`llama-server` + Qwen3-4B-Instruct-2507 GGUF instead of MLX/Qwen3-4B — MLX requires full Xcode's Metal build toolchain, unavailable on this machine. All spec guarantees (local, free, swappable model) preserved. Amendment must be appended to the spec file in Task 1.
- Data dir: `~/Library/Application Support/Ghostwriter/` · Bundle ID: `com.antoine.ghostwriter` · App name: **Ghostwriter** (one word).
- Commits: one logical unit per task, tree builds at every commit, `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` trailer.

**Execution notes for the implementer**
- Run everything from repo root `/Users/antoinetramble/CascadeProjects/Ghostwriter`.
- `swift test` runs only `GhostwriterCoreTests` (fast, no ML deps). ML/app targets are verified by building and by the Task 10 harness gate.
- Third-party API signatures (WhisperKit, GRDB, llama-server flags) are written as best-known; if a signature drifted, adapt the wrapper — **the protocol seams in Core are the contract and must not change.**

### File structure (locked in)

```
Package.swift
Sources/GhostwriterCore/        pure logic, no system deps beyond Foundation+GRDB
  WordDiff.swift  FillerLexicon.swift  FidelityGuardrail.swift
  DictionaryTerm.swift  AliasSubstituter.swift
  CleanupMode.swift  CleanupPrompt.swift  LLMOutputSanitizer.swift
  Transcriber.swift  TextCleaner.swift  DictationPipeline.swift
  AppDatabase.swift  Records.swift
Sources/GhostwriterML/          heavy deps, thin wrappers
  WhisperTranscriber.swift  LlamaServerCleaner.swift
Sources/Ghostwriter/            the app
  main.swift  AppDelegate.swift  StatusItemController.swift
  HotkeyService.swift  AudioCaptureService.swift  AppContextService.swift
  InsertionService.swift  HUDController.swift  DictationController.swift
  ModelManager.swift  AppState.swift
  UI/MainWindow.swift  UI/HistoryView.swift  UI/DictionaryView.swift
  UI/SettingsView.swift  UI/OnboardingView.swift
Sources/ghostwriter-harness/main.swift
Tests/GhostwriterCoreTests/     one test file per Core unit
Scripts/gen_fixtures.sh  Scripts/make_app.sh
Fixtures/*.wav                  committed synthetic audio
```

---

### Task 1: Package scaffold — deps resolve and build with CLT only

**Files:**
- Create: `Package.swift`, `.gitignore`, `Sources/GhostwriterCore/Placeholder.swift`, `Sources/GhostwriterML/Placeholder.swift`, `Sources/Ghostwriter/main.swift`, `Sources/ghostwriter-harness/main.swift`, `Tests/GhostwriterCoreTests/SmokeTests.swift`
- Modify: `docs/superpowers/specs/2026-07-20-ghostwriter-design.md` (append amendment)

**Interfaces:**
- Produces: the five-target package layout every later task drops files into.

- [ ] **Step 1: Write Package.swift**

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Ghostwriter",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
    ],
    targets: [
        .target(
            name: "GhostwriterCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .target(
            name: "GhostwriterML",
            dependencies: [
                "GhostwriterCore",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]),
        .executableTarget(
            name: "Ghostwriter",
            dependencies: ["GhostwriterCore", "GhostwriterML"]),
        .executableTarget(
            name: "ghostwriter-harness",
            dependencies: ["GhostwriterCore", "GhostwriterML"]),
        .testTarget(
            name: "GhostwriterCoreTests",
            dependencies: ["GhostwriterCore"]),
    ]
)
```

- [ ] **Step 2: Create stubs and .gitignore**

`.gitignore`:
```
.build/
.swiftpm/
*.app
Fixtures/tmp/
```

`Sources/GhostwriterCore/Placeholder.swift`: `public enum GhostwriterCore { public static let version = "1.0.0" }`
`Sources/GhostwriterML/Placeholder.swift`: `import GhostwriterCore\nenum GhostwriterML {}`
`Sources/Ghostwriter/main.swift`: `print("Ghostwriter app placeholder")`
`Sources/ghostwriter-harness/main.swift`: `print("harness placeholder")`
`Tests/GhostwriterCoreTests/SmokeTests.swift`:
```swift
import XCTest
@testable import GhostwriterCore
final class SmokeTests: XCTestCase {
    func testVersion() { XCTAssertEqual(GhostwriterCore.version, "1.0.0") }
}
```

- [ ] **Step 3: Resolve + build + test.** Run `swift build && swift test`. Expected: both succeed. **This is the fail-fast gate for WhisperKit/GRDB compiling under CLT.** If WhisperKit fails to build, fall back plan: replace with brew `whisper-cpp` + server subprocess mirroring the LlamaServerCleaner pattern (do not change the `Transcriber` protocol).

- [ ] **Step 4: Append spec amendment** (llama.cpp substitution, wording from Global Constraints) to the spec file.

- [ ] **Step 5: Commit** `feat: scaffold SwiftPM package (Core/ML/app/harness/tests)`

---

### Task 2: WordDiff (TDD)

**Files:** Create `Sources/GhostwriterCore/WordDiff.swift`, `Tests/GhostwriterCoreTests/WordDiffTests.swift`

**Interfaces:**
- Produces: `WordDiff.normalize(_ text: String) -> [String]`, `WordDiff.diff(_ a: [String], _ b: [String]) -> [WordDiff.Op]` with `Op = .equal(String) | .delete(String) | .insert(String)`. Consumed by Task 3.

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import GhostwriterCore

final class WordDiffTests: XCTestCase {
    func testNormalizeStripsPunctuationAndCase() {
        XCTAssertEqual(WordDiff.normalize("Hello, World! It's 5 o'clock."),
                       ["hello", "world", "it's", "5", "o'clock"])
    }
    func testNormalizeEmpty() { XCTAssertEqual(WordDiff.normalize("  ,. "), []) }
    func testDiffEqual() {
        XCTAssertEqual(WordDiff.diff(["a", "b"], ["a", "b"]), [.equal("a"), .equal("b")])
    }
    func testDiffDeletion() {
        XCTAssertEqual(WordDiff.diff(["um", "hello"], ["hello"]), [.delete("um"), .equal("hello")])
    }
    func testDiffInsertion() {
        XCTAssertEqual(WordDiff.diff(["hello"], ["oh", "hello"]), [.insert("oh"), .equal("hello")])
    }
    func testDiffSubstitutionIsDeletePlusInsert() {
        let ops = WordDiff.diff(["send", "tuesday"], ["send", "wednesday"])
        XCTAssertEqual(ops, [.equal("send"), .delete("tuesday"), .insert("wednesday")])
    }
}
```

- [ ] **Step 2: Run — expect FAIL** (`WordDiff` undefined): `swift test --filter WordDiffTests`

- [ ] **Step 3: Implement**

```swift
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
```

- [ ] **Step 4: Run — expect PASS.**  - [ ] **Step 5: Commit** `feat: LCS word diff with dictation-oriented normalization`

---

### Task 3: FillerLexicon + FidelityGuardrail (TDD) — the anti-Wispr-Flow core

**Files:** Create `Sources/GhostwriterCore/FillerLexicon.swift`, `Sources/GhostwriterCore/FidelityGuardrail.swift`, `Tests/GhostwriterCoreTests/FidelityGuardrailTests.swift`

**Interfaces:**
- Consumes: `WordDiff` (Task 2).
- Produces: `FidelityGuardrail.evaluate(raw: String, cleaned: String, threshold: Double = 0.15) -> GuardrailVerdict` where `GuardrailVerdict { accepted: Bool, penalty: Double, allowance: Double }`; `FillerLexicon.words: Set<String>`, `.phrases: [String]`, `.isFiller(_:) -> Bool`. Consumed by Task 7.

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import GhostwriterCore

final class FidelityGuardrailTests: XCTestCase {
    func testIdenticalTextAccepted() {
        let v = FidelityGuardrail.evaluate(raw: "ship the fix today", cleaned: "Ship the fix today.")
        XCTAssertTrue(v.accepted); XCTAssertEqual(v.penalty, 0)
    }
    func testFillerRemovalIsFree() {
        let v = FidelityGuardrail.evaluate(
            raw: "um so basically I want uh the button blue you know",
            cleaned: "So basically I want the button blue.")
        XCTAssertTrue(v.accepted); XCTAssertEqual(v.penalty, 0)
    }
    func testSelfCorrectionSpanIsFree() {
        let v = FidelityGuardrail.evaluate(
            raw: "send it Tuesday no wait send it Wednesday morning",
            cleaned: "Send it Wednesday morning.")
        XCTAssertTrue(v.accepted)
    }
    func testFullRewriteRejected() {
        let v = FidelityGuardrail.evaluate(
            raw: "make the login page way faster please it is really slow for users",
            cleaned: "Optimize authentication latency to improve user experience.")
        XCTAssertFalse(v.accepted)
    }
    func testEmptyCleanedRejected() {
        XCTAssertFalse(FidelityGuardrail.evaluate(raw: "hello there", cleaned: "").accepted)
    }
    func testEmptyRawAccepted() {
        XCTAssertTrue(FidelityGuardrail.evaluate(raw: "", cleaned: "").accepted)
    }
    func testShortUtteranceSmallInsertRejected() {
        // 3-word utterance, 2 inserted words -> penalty 2.0 > allowance max(0.45, 1.5)
        let v = FidelityGuardrail.evaluate(raw: "fix the bug", cleaned: "please kindly fix the bug")
        XCTAssertFalse(v.accepted)
    }
    func testModestNonFillerDeletionTolerated() {
        // deleting 2 non-filler words costs 0.5, allowance >= 1.5
        let v = FidelityGuardrail.evaluate(
            raw: "so yeah make the header sticky on scroll",
            cleaned: "Make the header sticky on scroll.")
        XCTAssertTrue(v.accepted)
    }
}
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement**

`FillerLexicon.swift`:
```swift
public enum FillerLexicon {
    public static let words: Set<String> =
        ["um", "uh", "uhm", "umm", "erm", "er", "ah", "hmm", "mhm", "hm", "yeah", "so", "like", "basically"]
    /// Multi-word fillers, matched inside deleted spans only.
    public static let phrases: [String] = ["you know", "kind of", "sort of", "i mean"]
    public static func isFiller(_ word: String) -> Bool { words.contains(word) }
}
```
Note: `so`/`like`/`basically`/`yeah` are only "free to DELETE" — the guardrail never removes anything itself, so listing them costs nothing and lets the cleaner drop leading discourse markers.

`FidelityGuardrail.swift`:
```swift
public struct GuardrailVerdict: Equatable {
    public let accepted: Bool
    public let penalty: Double
    public let allowance: Double
    public init(accepted: Bool, penalty: Double, allowance: Double) {
        self.accepted = accepted; self.penalty = penalty; self.allowance = allowance
    }
}

public enum FidelityGuardrail {
    public static let defaultThreshold = 0.15
    static let correctionMarkers = ["no wait", "i mean", "scratch that", "no actually", "wait no", "rather", "wait"]

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
```

- [ ] **Step 4: Run — expect PASS.** Tune only test fixtures never thresholds if a case sits on the boundary; thresholds are spec values.
- [ ] **Step 5: Commit** `feat: fidelity guardrail — rewrites structurally impossible`

---

### Task 4: DictionaryTerm + AliasSubstituter (TDD)

**Files:** Create `Sources/GhostwriterCore/DictionaryTerm.swift`, `Sources/GhostwriterCore/AliasSubstituter.swift`, `Tests/GhostwriterCoreTests/AliasSubstituterTests.swift`

**Interfaces:**
- Produces: `struct DictionaryTerm: Codable, Equatable { var id: Int64?; var term: String; var aliases: [String] }` and `AliasSubstituter.apply(_ text: String, terms: [DictionaryTerm]) -> String`. Consumed by Tasks 6, 7.

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import GhostwriterCore

final class AliasSubstituterTests: XCTestCase {
    let terms = [
        DictionaryTerm(term: "Supabase", aliases: ["super base", "soup abase"]),
        DictionaryTerm(term: "Ghostwriter", aliases: ["ghost writer"]),
        DictionaryTerm(term: "GRDB", aliases: ["g r d b"]),
    ]
    func testMultiWordAliasReplaced() {
        XCTAssertEqual(AliasSubstituter.apply("push it to super base now", terms: terms),
                       "push it to Supabase now")
    }
    func testCaseInsensitiveMatch() {
        XCTAssertEqual(AliasSubstituter.apply("Ghost Writer is live", terms: terms),
                       "Ghostwriter is live")
    }
    func testNoPartialWordMatch() {
        XCTAssertEqual(AliasSubstituter.apply("superbases are cool", terms: terms),
                       "superbases are cool")
    }
    func testCanonicalSpellingEnforcedOnTermItself() {
        // saying the term itself but transcribed with wrong casing
        let t = [DictionaryTerm(term: "WhisperKit", aliases: [])]
        XCTAssertEqual(AliasSubstituter.apply("use whisperkit here", terms: t), "use WhisperKit here")
    }
    func testEmptyTerms() {
        XCTAssertEqual(AliasSubstituter.apply("hello", terms: []), "hello")
    }
}
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement**

`DictionaryTerm.swift`:
```swift
public struct DictionaryTerm: Codable, Equatable {
    public var id: Int64?
    public var term: String
    public var aliases: [String]
    public init(id: Int64? = nil, term: String, aliases: [String] = []) {
        self.id = id; self.term = term; self.aliases = aliases
    }
}
```

`AliasSubstituter.swift`:
```swift
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
        // longest alias first so "soup abase base" style overlaps resolve sanely
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
```

- [ ] **Step 4: Run — expect PASS.**  - [ ] **Step 5: Commit** `feat: dictionary terms with deterministic alias substitution`

---

### Task 5: CleanupMode + CleanupPrompt + LLMOutputSanitizer (TDD)

**Files:** Create `Sources/GhostwriterCore/CleanupMode.swift`, `Sources/GhostwriterCore/CleanupPrompt.swift`, `Sources/GhostwriterCore/LLMOutputSanitizer.swift`, `Tests/GhostwriterCoreTests/CleanupPromptTests.swift`

**Interfaces:**
- Produces: `enum CleanupMode: String, Codable, CaseIterable { case lightTouch, verbatimTechnical, raw }`; `CleanupPrompt.system(mode: CleanupMode, dictionaryTerms: [String]) -> String`; `LLMOutputSanitizer.sanitize(_ s: String) -> String`. Consumed by Tasks 6, 7, 9.

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import GhostwriterCore

final class CleanupPromptTests: XCTestCase {
    func testLightTouchForbidsRephrasing() {
        let p = CleanupPrompt.system(mode: .lightTouch, dictionaryTerms: [])
        XCTAssertTrue(p.contains("NEVER rephrase"))
    }
    func testTechnicalModeMentionsVerbatim() {
        let p = CleanupPrompt.system(mode: .verbatimTechnical, dictionaryTerms: [])
        XCTAssertTrue(p.contains("technical term"))
    }
    func testDictionaryTermsIncluded() {
        let p = CleanupPrompt.system(mode: .lightTouch, dictionaryTerms: ["Supabase", "GRDB"])
        XCTAssertTrue(p.contains("Supabase, GRDB"))
    }
    func testSanitizerStripsThinkBlocks() {
        XCTAssertEqual(LLMOutputSanitizer.sanitize("<think>hmm</think>\nFix the bug."), "Fix the bug.")
    }
    func testSanitizerStripsUnterminatedThink() {
        XCTAssertEqual(LLMOutputSanitizer.sanitize("<think>rambling forever"), "")
    }
    func testSanitizerStripsWrappingQuotes() {
        XCTAssertEqual(LLMOutputSanitizer.sanitize("\"Fix the bug.\""), "Fix the bug.")
    }
    func testSanitizerCollapsesBlankLines() {
        XCTAssertEqual(LLMOutputSanitizer.sanitize("a\n\n\n\nb"), "a\n\nb")
    }
}
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement**

`CleanupMode.swift`:
```swift
public enum CleanupMode: String, Codable, CaseIterable, Sendable {
    case lightTouch, verbatimTechnical, raw

    public var displayName: String {
        switch self {
        case .lightTouch: return "Light touch"
        case .verbatimTechnical: return "Verbatim technical"
        case .raw: return "Raw (no AI)"
        }
    }
}
```

`CleanupPrompt.swift` (copy prompt text verbatim — it is load-bearing):
```swift
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
```

`LLMOutputSanitizer.swift`:
```swift
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
```

- [ ] **Step 4: Run — expect PASS.**  - [ ] **Step 5: Commit** `feat: cleanup modes, system prompts, LLM output sanitizer`

---

### Task 6: Persistence — AppDatabase, records, FTS5 search (TDD)

**Files:** Create `Sources/GhostwriterCore/Records.swift`, `Sources/GhostwriterCore/AppDatabase.swift`, `Tests/GhostwriterCoreTests/AppDatabaseTests.swift`

**Interfaces:**
- Consumes: `DictionaryTerm`, `CleanupMode`.
- Produces (consumed by Tasks 13, 15, 16, 17):
  - `struct DictationRecord { id, createdAt, rawText, cleanedText, appBundleID: String?, durationSec, usedFallback, profileUsed }`
  - `final class AppDatabase` with `init(path: String)` and `static func inMemory()`, methods:
    `saveDictation(_:) throws -> DictationRecord`, `recentDictations(limit: Int) throws -> [DictationRecord]`,
    `searchDictations(_ query: String) throws -> [DictationRecord]`,
    `allTerms() throws -> [DictionaryTerm]`, `addTerm(_:) throws`, `deleteTerm(id: Int64) throws`,
    `mode(forBundleID: String?) throws -> CleanupMode`, `setMode(_ mode: CleanupMode, forBundleID: String) throws`,
    `removeProfile(bundleID: String) throws`, `allProfiles() throws -> [(bundleID: String, mode: CleanupMode)]`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import GhostwriterCore

final class AppDatabaseTests: XCTestCase {
    var db: AppDatabase!
    override func setUpWithError() throws { db = try AppDatabase.inMemory() }

    func testSaveAndFetchDictation() throws {
        var rec = DictationRecord(createdAt: Date(), rawText: "um hello", cleanedText: "Hello.",
                                  appBundleID: "com.apple.Terminal", durationSec: 2.5,
                                  usedFallback: false, profileUsed: "verbatimTechnical")
        rec = try db.saveDictation(rec)
        XCTAssertNotNil(rec.id)
        XCTAssertEqual(try db.recentDictations(limit: 10).first?.cleanedText, "Hello.")
    }
    func testFullTextSearch() throws {
        _ = try db.saveDictation(DictationRecord(createdAt: Date(), rawText: "deploy the supabase migration",
            cleanedText: "Deploy the Supabase migration.", appBundleID: nil, durationSec: 3,
            usedFallback: false, profileUsed: "lightTouch"))
        _ = try db.saveDictation(DictationRecord(createdAt: Date(), rawText: "buy milk",
            cleanedText: "Buy milk.", appBundleID: nil, durationSec: 1,
            usedFallback: false, profileUsed: "lightTouch"))
        let hits = try db.searchDictations("supabase")
        XCTAssertEqual(hits.count, 1)
        XCTAssertTrue(hits[0].cleanedText.contains("Supabase"))
    }
    func testDictionaryCRUD() throws {
        try db.addTerm(DictionaryTerm(term: "Ghostwriter", aliases: ["ghost writer"]))
        var terms = try db.allTerms()
        XCTAssertEqual(terms.map(\.term), ["Ghostwriter"])
        try db.deleteTerm(id: terms[0].id!)
        terms = try db.allTerms()
        XCTAssertTrue(terms.isEmpty)
    }
    func testProfilesSeededAndOverridable() throws {
        XCTAssertEqual(try db.mode(forBundleID: "com.apple.Terminal"), .verbatimTechnical)
        XCTAssertEqual(try db.mode(forBundleID: "com.unknown.app"), .lightTouch)
        XCTAssertEqual(try db.mode(forBundleID: nil), .lightTouch)
        try db.setMode(.raw, forBundleID: "com.unknown.app")
        XCTAssertEqual(try db.mode(forBundleID: "com.unknown.app"), .raw)
    }
}
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement**

`Records.swift`:
```swift
import Foundation
import GRDB

public struct DictationRecord: Codable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "dictation"
    public var id: Int64?
    public var createdAt: Date
    public var rawText: String
    public var cleanedText: String
    public var appBundleID: String?
    public var durationSec: Double
    public var usedFallback: Bool
    public var profileUsed: String

    public init(id: Int64? = nil, createdAt: Date, rawText: String, cleanedText: String,
                appBundleID: String?, durationSec: Double, usedFallback: Bool, profileUsed: String) {
        self.id = id; self.createdAt = createdAt; self.rawText = rawText
        self.cleanedText = cleanedText; self.appBundleID = appBundleID
        self.durationSec = durationSec; self.usedFallback = usedFallback; self.profileUsed = profileUsed
    }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

extension DictionaryTerm: FetchableRecord, MutablePersistableRecord {
    public static var databaseTableName: String { "dictionaryTerm" }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

struct AppProfileRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "appProfile"
    var bundleID: String
    var mode: String
}
```

`AppDatabase.swift`:
```swift
import Foundation
import GRDB

public final class AppDatabase {
    let dbQueue: DatabaseQueue

    public static let defaultSeededTechnicalApps = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.microsoft.VSCode",
        "com.exafunction.windsurf", "com.todesktop.230313mzl4w4u92", // Cursor
        "com.apple.dt.Xcode", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
    ]

    public init(path: String) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        dbQueue = try DatabaseQueue(path: path)
        try migrator.migrate(dbQueue)
    }

    public static func inMemory() throws -> AppDatabase { try AppDatabase(queue: DatabaseQueue()) }
    private init(queue: DatabaseQueue) throws {
        dbQueue = queue
        try migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "dictation") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("rawText", .text).notNull()
                t.column("cleanedText", .text).notNull()
                t.column("appBundleID", .text)
                t.column("durationSec", .double).notNull()
                t.column("usedFallback", .boolean).notNull()
                t.column("profileUsed", .text).notNull()
            }
            try db.create(virtualTable: "dictation_ft", using: FTS5()) { t in
                t.synchronize(withTable: "dictation")
                t.column("rawText"); t.column("cleanedText")
            }
            try db.create(table: "dictionaryTerm") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("term", .text).notNull().unique()
                t.column("aliases", .text).notNull()   // JSON array via Codable
            }
            try db.create(table: "appProfile") { t in
                t.column("bundleID", .text).primaryKey()
                t.column("mode", .text).notNull()
            }
            for bundle in Self.defaultSeededTechnicalApps {
                try AppProfileRecord(bundleID: bundle, mode: CleanupMode.verbatimTechnical.rawValue).insert(db)
            }
        }
        return m
    }

    // MARK: Dictations
    public func saveDictation(_ rec: DictationRecord) throws -> DictationRecord {
        try dbQueue.write { db in var r = rec; try r.insert(db); return r }
    }
    public func recentDictations(limit: Int = 200) throws -> [DictationRecord] {
        try dbQueue.read { db in
            try DictationRecord.order(Column("createdAt").desc).limit(limit).fetchAll(db)
        }
    }
    public func searchDictations(_ query: String) throws -> [DictationRecord] {
        let tokens = query.split(separator: " ").map { "\"\($0)\"" }.joined(separator: " ")
        guard !tokens.isEmpty else { return try recentDictations() }
        return try dbQueue.read { db in
            try DictationRecord.fetchAll(db, sql: """
                SELECT dictation.* FROM dictation
                JOIN dictation_ft ON dictation_ft.rowid = dictation.id
                WHERE dictation_ft MATCH ?
                ORDER BY createdAt DESC LIMIT 200
                """, arguments: [tokens])
        }
    }

    // MARK: Dictionary
    public func allTerms() throws -> [DictionaryTerm] {
        try dbQueue.read { db in try DictionaryTerm.order(Column("term")).fetchAll(db) }
    }
    public func addTerm(_ term: DictionaryTerm) throws {
        try dbQueue.write { db in var t = term; try t.insert(db) }
    }
    public func deleteTerm(id: Int64) throws {
        _ = try dbQueue.write { db in try DictionaryTerm.deleteOne(db, key: id) }
    }

    // MARK: App profiles
    public func mode(forBundleID bundleID: String?) throws -> CleanupMode {
        guard let bundleID else { return .lightTouch }
        return try dbQueue.read { db in
            guard let rec = try AppProfileRecord.fetchOne(db, key: bundleID),
                  let mode = CleanupMode(rawValue: rec.mode) else { return .lightTouch }
            return mode
        }
    }
    public func setMode(_ mode: CleanupMode, forBundleID bundleID: String) throws {
        try dbQueue.write { db in
            try AppProfileRecord(bundleID: bundleID, mode: mode.rawValue).save(db)
        }
    }
    public func removeProfile(bundleID: String) throws {
        _ = try dbQueue.write { db in try AppProfileRecord.deleteOne(db, key: bundleID) }
    }
    public func allProfiles() throws -> [(bundleID: String, mode: CleanupMode)] {
        try dbQueue.read { db in
            try AppProfileRecord.order(Column("bundleID")).fetchAll(db)
                .compactMap { r in CleanupMode(rawValue: r.mode).map { (r.bundleID, $0) } }
        }
    }
}
```

- [ ] **Step 4: Run — expect PASS** (`swift test --filter AppDatabaseTests`). GRDB API drift (e.g. `synchronize(withTable:)`, `didInsert`) → adapt implementation, keep test behavior identical.
- [ ] **Step 5: Commit** `feat: GRDB persistence — history with FTS5, dictionary, app profiles`

---

### Task 7: DictationPipeline with protocol seams (TDD)

**Files:** Create `Sources/GhostwriterCore/Transcriber.swift`, `Sources/GhostwriterCore/TextCleaner.swift`, `Sources/GhostwriterCore/DictationPipeline.swift`, `Tests/GhostwriterCoreTests/DictationPipelineTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 3–5.
- Produces (the app's spine — consumed by Tasks 8, 9, 10, 15):
  - `protocol Transcriber: AnyObject { func transcribe(audio: [Float], contextPrompt: String?) async throws -> String }`
  - `protocol TextCleaner: AnyObject { func clean(transcript: String, systemPrompt: String) async throws -> String }`
  - `struct PipelineResult: Equatable { rawText, finalText: String; usedFallback: Bool; mode: CleanupMode; errorDescription: String? }`
  - `final class DictationPipeline { init(transcriber: Transcriber, cleaner: TextCleaner?, cleanupTimeout: TimeInterval = 20); func process(audio: [Float], mode: CleanupMode, dictionary: [DictionaryTerm], guardrailThreshold: Double = FidelityGuardrail.defaultThreshold) async -> PipelineResult }`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
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

final class DictationPipelineTests: XCTestCase {
    let terms = [DictionaryTerm(term: "Supabase", aliases: ["super base"])]

    func testHappyPathUsesCleanedText() async {
        let t = FakeTranscriber(); t.result = .success("um push it to super base")
        let c = FakeCleaner(); c.result = .success("Push it to super base.")
        let r = await DictationPipeline(transcriber: t, cleaner: c)
            .process(audio: [0], mode: .lightTouch, dictionary: terms)
        XCTAssertEqual(r.finalText, "Push it to Supabase.")   // alias pass runs after cleanup
        XCTAssertFalse(r.usedFallback)
        XCTAssertEqual(t.receivedPrompt, "Glossary: Supabase.")
    }
    func testOverreachFallsBackToRawWithAliasPass() async {
        let t = FakeTranscriber(); t.result = .success("make the login page way faster please it is slow")
        let c = FakeCleaner(); c.result = .success("Optimize authentication latency for improved UX.")
        let r = await DictationPipeline(transcriber: t, cleaner: c)
            .process(audio: [0], mode: .lightTouch, dictionary: [])
        XCTAssertTrue(r.usedFallback)
        XCTAssertEqual(r.finalText, "make the login page way faster please it is slow")
    }
    func testCleanerErrorFallsBackToRaw() async {
        let t = FakeTranscriber(); t.result = .success("hello world")
        let c = FakeCleaner(); c.result = .failure(FakeError())
        let r = await DictationPipeline(transcriber: t, cleaner: c)
            .process(audio: [0], mode: .lightTouch, dictionary: [])
        XCTAssertTrue(r.usedFallback); XCTAssertEqual(r.finalText, "hello world")
    }
    func testCleanerTimeoutFallsBackToRaw() async {
        let t = FakeTranscriber(); t.result = .success("hello world")
        let c = FakeCleaner(); c.result = .success("Hello world."); c.delay = 5
        let p = DictationPipeline(transcriber: t, cleaner: c, cleanupTimeout: 0.05)
        let r = await p.process(audio: [0], mode: .lightTouch, dictionary: [])
        XCTAssertTrue(r.usedFallback); XCTAssertEqual(r.finalText, "hello world")
    }
    func testRawModeSkipsCleaner() async {
        let t = FakeTranscriber(); t.result = .success("um hello")
        let c = FakeCleaner(); c.result = .failure(FakeError())   // would explode if called
        let r = await DictationPipeline(transcriber: t, cleaner: c)
            .process(audio: [0], mode: .raw, dictionary: [])
        XCTAssertEqual(r.finalText, "um hello"); XCTAssertFalse(r.usedFallback)
    }
    func testNilCleanerActsAsRaw() async {
        let t = FakeTranscriber(); t.result = .success("um hello")
        let r = await DictationPipeline(transcriber: t, cleaner: nil)
            .process(audio: [0], mode: .lightTouch, dictionary: [])
        XCTAssertEqual(r.finalText, "um hello")
    }
    func testTranscriberErrorReported() async {
        let t = FakeTranscriber(); t.result = .failure(FakeError())
        let r = await DictationPipeline(transcriber: t, cleaner: nil)
            .process(audio: [0], mode: .lightTouch, dictionary: [])
        XCTAssertNotNil(r.errorDescription); XCTAssertEqual(r.finalText, "")
    }
    func testEmptyTranscriptShortCircuits() async {
        let t = FakeTranscriber(); t.result = .success("   ")
        let r = await DictationPipeline(transcriber: t, cleaner: nil)
            .process(audio: [0], mode: .lightTouch, dictionary: [])
        XCTAssertEqual(r.finalText, ""); XCTAssertNil(r.errorDescription)
    }
    func testThinkBlocksSanitizedBeforeGuardrail() async {
        let t = FakeTranscriber(); t.result = .success("fix the bug now")
        let c = FakeCleaner(); c.result = .success("<think>user wants...</think>Fix the bug now.")
        let r = await DictationPipeline(transcriber: t, cleaner: c)
            .process(audio: [0], mode: .lightTouch, dictionary: [])
        XCTAssertEqual(r.finalText, "Fix the bug now."); XCTAssertFalse(r.usedFallback)
    }
}
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement**

`Transcriber.swift`:
```swift
public protocol Transcriber: AnyObject {
    /// contextPrompt biases recognition toward dictionary vocabulary.
    func transcribe(audio: [Float], contextPrompt: String?) async throws -> String
}
```

`TextCleaner.swift`:
```swift
public protocol TextCleaner: AnyObject {
    func clean(transcript: String, systemPrompt: String) async throws -> String
}
```

`DictationPipeline.swift`:
```swift
import Foundation

public struct PipelineResult: Equatable {
    public let rawText: String
    public let finalText: String
    public let usedFallback: Bool
    public let mode: CleanupMode
    public let errorDescription: String?
}

struct TimeoutError: Error {}

func withTimeout<T: Sendable>(_ seconds: TimeInterval,
                              _ body: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await body() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

public final class DictationPipeline {
    private let transcriber: Transcriber
    private let cleaner: TextCleaner?
    private let cleanupTimeout: TimeInterval

    public init(transcriber: Transcriber, cleaner: TextCleaner?, cleanupTimeout: TimeInterval = 20) {
        self.transcriber = transcriber; self.cleaner = cleaner; self.cleanupTimeout = cleanupTimeout
    }

    public func process(audio: [Float], mode: CleanupMode, dictionary: [DictionaryTerm],
                        guardrailThreshold: Double = FidelityGuardrail.defaultThreshold) async -> PipelineResult {
        let glossary = dictionary.map(\.term)
        let contextPrompt = glossary.isEmpty ? nil : "Glossary: " + glossary.joined(separator: ", ") + "."

        let rawText: String
        do {
            rawText = try await transcriber.transcribe(audio: audio, contextPrompt: contextPrompt)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return PipelineResult(rawText: "", finalText: "", usedFallback: false, mode: mode,
                                  errorDescription: "Transcription failed: \(error)")
        }
        guard !rawText.isEmpty else {
            return PipelineResult(rawText: "", finalText: "", usedFallback: false, mode: mode,
                                  errorDescription: nil)
        }

        var finalText = rawText
        var usedFallback = false
        if mode != .raw, let cleaner {
            let system = CleanupPrompt.system(mode: mode, dictionaryTerms: glossary)
            let timeout = cleanupTimeout
            let cleaned = try? await withTimeout(timeout) { [cleaner] in
                try await cleaner.clean(transcript: rawText, systemPrompt: system)
            }
            if let cleaned {
                let sanitized = LLMOutputSanitizer.sanitize(cleaned)
                let verdict = FidelityGuardrail.evaluate(raw: rawText, cleaned: sanitized,
                                                         threshold: guardrailThreshold)
                if verdict.accepted && !sanitized.isEmpty { finalText = sanitized }
                else { usedFallback = true }
            } else { usedFallback = true }
        }
        finalText = AliasSubstituter.apply(finalText, terms: dictionary)
        return PipelineResult(rawText: rawText, finalText: finalText,
                              usedFallback: usedFallback, mode: mode, errorDescription: nil)
    }
}
```

- [ ] **Step 4: Run full suite — expect PASS** (`swift test`).
- [ ] **Step 5: Commit** `feat: dictation pipeline — transcribe, clean, guardrail, alias pass`

---

### Task 8: WhisperTranscriber (WhisperKit wrapper)

**Files:** Create `Sources/GhostwriterML/WhisperTranscriber.swift` (delete `Placeholder.swift`)

**Interfaces:**
- Consumes: `Transcriber` protocol.
- Produces: `final class WhisperTranscriber: Transcriber { init(modelName: String = "large-v3-v20240930_turbo"); func preload(status: ((String) -> Void)?) async throws; var isLoaded: Bool; func unload() }`. Consumed by Tasks 10, 15, 17.

- [ ] **Step 1: Implement** (no unit test — CoreML wrapper; verified by build now, harness in Task 10)

```swift
import Foundation
import GhostwriterCore
import WhisperKit

public final class WhisperTranscriber: Transcriber {
    public let modelName: String
    private var pipe: WhisperKit?

    public init(modelName: String = "large-v3-v20240930_turbo") { self.modelName = modelName }

    public var isLoaded: Bool { pipe != nil }
    public func unload() { pipe = nil }

    /// Loads the model, downloading on first run (WhisperKit caches under Application Support).
    public func preload(status: ((String) -> Void)? = nil) async throws {
        guard pipe == nil else { return }
        status?("Loading speech model \(modelName)…")
        let config = WhisperKitConfig(model: modelName, download: true)
        pipe = try await WhisperKit(config)
        status?("Speech model ready.")
    }

    public func transcribe(audio: [Float], contextPrompt: String?) async throws -> String {
        try await preload()
        guard let pipe else { throw NSError(domain: "Ghostwriter", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Whisper model not loaded"]) }
        var options = DecodingOptions()
        options.language = "en"
        options.temperature = 0
        options.chunkingStrategy = .vad
        if let contextPrompt, let tokenizer = pipe.tokenizer {
            // Prompt conditioning: glossary becomes decoding context (spec §4).
            let tokens = tokenizer.encode(text: " " + contextPrompt)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            options.promptTokens = tokens
            options.usePrefillPrompt = true
        }
        let results = try await pipe.transcribe(audioArray: audio, decodeOptions: options)
        return results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 2: Build** `swift build --target GhostwriterML`. Expected: succeeds. If WhisperKit's API drifted (`WhisperKitConfig`, `specialTokens`, `chunkingStrategy`), adapt here only; check `.build/checkouts/WhisperKit/Sources/WhisperKit/Core/` for current signatures.
- [ ] **Step 3: Commit** `feat: WhisperKit transcriber with glossary prompt conditioning`

---

### Task 9: LlamaServerCleaner (managed llama-server subprocess)

**Files:** Create `Sources/GhostwriterML/LlamaServerCleaner.swift`

**Interfaces:**
- Consumes: `TextCleaner` protocol.
- Produces (consumed by Tasks 10, 15, 17): `final class LlamaServerCleaner: TextCleaner` with
  `init(serverBinary: URL = /opt/homebrew/bin/llama-server, modelSpec: String = "unsloth/Qwen3-4B-Instruct-2507-GGUF:Q4_K_M", port: Int = 8873)`,
  `func ensureRunning(readyTimeout: TimeInterval, status: ((String) -> Void)?) async throws`,
  `func shutdown()`, `var isRunning: Bool`, `static func binaryExists() -> Bool`.

- [ ] **Step 1: Implement**

```swift
import Foundation
import GhostwriterCore

public final class LlamaServerCleaner: TextCleaner {
    public static let defaultBinary = URL(fileURLWithPath: "/opt/homebrew/bin/llama-server")
    public static let defaultModelSpec = "unsloth/Qwen3-4B-Instruct-2507-GGUF:Q4_K_M"

    private let serverBinary: URL
    private let modelSpec: String
    private let port: Int
    private var process: Process?
    private let session: URLSession

    public init(serverBinary: URL = LlamaServerCleaner.defaultBinary,
                modelSpec: String = LlamaServerCleaner.defaultModelSpec,
                port: Int = 8873) {
        self.serverBinary = serverBinary; self.modelSpec = modelSpec; self.port = port
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 60
        session = URLSession(configuration: cfg)
    }

    public static func binaryExists() -> Bool {
        FileManager.default.isExecutableFile(atPath: defaultBinary.path)
    }
    public var isRunning: Bool { process?.isRunning ?? false }

    private var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }

    /// Starts llama-server if not already healthy. First run downloads the GGUF
    /// (~2.4 GB, cached in ~/Library/Caches/llama.cpp) — pass a generous readyTimeout then.
    public func ensureRunning(readyTimeout: TimeInterval = 90,
                              status: ((String) -> Void)? = nil) async throws {
        if await isHealthy() { return }
        if process?.isRunning != true {
            status?("Starting cleanup model…")
            let p = Process()
            p.executableURL = serverBinary
            p.arguments = ["-hf", modelSpec,
                           "--host", "127.0.0.1", "--port", "\(port)",
                           "-c", "4096", "-ngl", "99", "--no-webui"]
            let logURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Ghostwriter/llama-server.log")
            try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            let log = try? FileHandle(forWritingTo: logURL)
            p.standardOutput = log; p.standardError = log
            try p.run()
            process = p
        }
        let deadline = Date().addingTimeInterval(readyTimeout)
        while Date() < deadline {
            if await isHealthy() { status?("Cleanup model ready."); return }
            if process?.isRunning != true {
                throw NSError(domain: "Ghostwriter", code: 2, userInfo: [NSLocalizedDescriptionKey:
                    "llama-server exited early — see ~/Library/Application Support/Ghostwriter/llama-server.log"])
            }
            status?("Waiting for cleanup model… (first run downloads ~2.4 GB)")
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw NSError(domain: "Ghostwriter", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "llama-server not ready in \(Int(readyTimeout))s"])
    }

    private func isHealthy() async -> Bool {
        var req = URLRequest(url: baseURL.appendingPathComponent("health"))
        req.timeoutInterval = 2
        guard let (_, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
        return true
    }

    public func clean(transcript: String, systemPrompt: String) async throws -> String {
        try await ensureRunning()
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": transcript],
            ],
            "temperature": 0,
            "max_tokens": 2048,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "Ghostwriter", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Bad llama-server response"])
        }
        return content
    }

    public func shutdown() { process?.terminate(); process = nil }
}
```

- [ ] **Step 2: Build** `swift build --target GhostwriterML`. Expected: succeeds.
- [ ] **Step 3: Commit** `feat: llama-server text cleaner (Qwen3-4B-Instruct, temperature 0)`

---

### Task 10: Harness CLI + fixtures + REAL end-to-end gate

This is the milestone that proves the whole pipeline on real audio with real models. Everything after it is app shell.

**Files:** Create `Sources/ghostwriter-harness/main.swift` (replace placeholder), `Scripts/gen_fixtures.sh`, `Fixtures/*.wav` (generated, committed)

**Interfaces:**
- Consumes: `DictationPipeline`, `WhisperTranscriber`, `LlamaServerCleaner`, `AudioProcessor` (WhisperKit).
- Produces: `ghostwriter-harness <file.wav> [--mode lightTouch|verbatimTechnical|raw] [--terms "A,B"] [--aliases "alias=Term;..."] [--no-clean]` printing RAW/FINAL/fallback/timings.

- [ ] **Step 1: Fixture generator** `Scripts/gen_fixtures.sh` (chmod +x):

```bash
#!/bin/bash
# Synthesizes dictation-like WAVs (16 kHz mono) with macOS TTS - micless E2E audio.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Fixtures /tmp/gw_fixtures

gen() {
  say -v Samantha -o "/tmp/gw_fixtures/$1.aiff" "$2"
  afconvert -f WAVE -d LEI16@16000 -c 1 "/tmp/gw_fixtures/$1.aiff" "Fixtures/$1.wav"
  echo "Fixtures/$1.wav"
}

gen basic "Um, so basically I want you to, uh, refactor the login page and, um, make the button blue."
gen correction "Send the invoice on Tuesday. No wait, send it on Wednesday morning."
gen technical "Open ghostwriter dot swift and add a function called handle hotkey that calls the transcription service."
gen vibecoding "Add a use effect hook that fetches the user profile from supabase and, um, put a loading spinner while it waits."
```

- [ ] **Step 2: Harness main.swift**

```swift
import Foundation
import GhostwriterCore
import GhostwriterML
import WhisperKit

@main
struct Harness {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        guard let wavPath = args.first, !wavPath.hasPrefix("--") else {
            print("usage: ghostwriter-harness <file.wav> [--mode lightTouch|verbatimTechnical|raw] [--terms \"A,B\"] [--aliases \"alias=Term;alias2=Term2\"] [--no-clean]")
            exit(2)
        }
        args.removeFirst()
        func flag(_ name: String) -> String? {
            guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        let mode = CleanupMode(rawValue: flag("--mode") ?? "lightTouch") ?? .lightTouch
        let noClean = args.contains("--no-clean")
        var terms: [DictionaryTerm] = (flag("--terms") ?? "").split(separator: ",")
            .map { DictionaryTerm(term: $0.trimmingCharacters(in: .whitespaces)) }
        for pair in (flag("--aliases") ?? "").split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            if let i = terms.firstIndex(where: { $0.term == kv[1] }) { terms[i].aliases.append(kv[0]) }
            else { terms.append(DictionaryTerm(term: kv[1], aliases: [kv[0]])) }
        }

        do {
            let buffer = try AudioProcessor.loadAudio(fromPath: wavPath)
            let audio = AudioProcessor.convertBufferToArray(buffer: buffer)
            print("Audio: \(wavPath)  (\(String(format: "%.1f", Double(audio.count) / 16000))s)")

            let transcriber = WhisperTranscriber()
            let t0 = Date()
            try await transcriber.preload { print("  [status] \($0)") }
            print("Model load: \(String(format: "%.2f", -t0.timeIntervalSinceNow))s")

            var cleaner: LlamaServerCleaner?
            if !noClean && mode != .raw {
                let c = LlamaServerCleaner()
                try await c.ensureRunning(readyTimeout: 1800) { print("  [status] \($0)") }
                cleaner = c
            }

            let pipeline = DictationPipeline(transcriber: transcriber, cleaner: cleaner)
            let t1 = Date()
            let result = await pipeline.process(audio: audio, mode: mode, dictionary: terms)
            let elapsed = -t1.timeIntervalSinceNow

            print("\nRAW:      \(result.rawText)")
            print("FINAL:    \(result.finalText)")
            print("FALLBACK: \(result.usedFallback)  MODE: \(result.mode.rawValue)")
            if let err = result.errorDescription { print("ERROR:    \(err)") }
            print("Pipeline time (warm): \(String(format: "%.2f", elapsed))s")
            cleaner?.shutdown()
            exit(result.errorDescription == nil ? 0 : 1)
        } catch {
            print("FAILED: \(error)"); exit(1)
        }
    }
}
```
Note: `@main` requires deleting the placeholder top-level code; keep the file named `main.swift`→ rename to `Harness.swift` if `@main` conflicts (SwiftPM forbids `@main` in `main.swift`).

- [ ] **Step 3: Install llama.cpp + generate fixtures.** Run: `brew install llama.cpp && ./Scripts/gen_fixtures.sh`. Expected: 4 WAVs in `Fixtures/`.

- [ ] **Step 4: THE GATE — run E2E on all fixtures.** (First run downloads Whisper turbo ~1.6 GB + Qwen ~2.4 GB; allow time. Disk has ~19 GB free — enough, but verify with `df -h` after.)

```bash
swift run -c release ghostwriter-harness Fixtures/basic.wav
swift run -c release ghostwriter-harness Fixtures/correction.wav
swift run -c release ghostwriter-harness Fixtures/technical.wav --mode verbatimTechnical
swift run -c release ghostwriter-harness Fixtures/vibecoding.wav --terms "Supabase,useEffect" --aliases "use effect=useEffect;supa base=Supabase"
swift run -c release ghostwriter-harness Fixtures/basic.wav --no-clean
```

Expected, for each: RAW is a faithful transcription; FINAL has fillers removed / correction applied / dictionary casing right; FALLBACK false on all (raw fallback acceptable on `correction` only if guardrail flags it — inspect and record actual outputs in the commit message); warm pipeline time ≤ ~3s for these ~6–10s clips in debug-run conditions.
**Do not proceed past this gate until all five runs behave.** Debug in this order: RAW wrong → Whisper config; FINAL wrong → prompt or sanitizer; FALLBACK unexpectedly true → print `GuardrailVerdict` numbers and inspect the diff ops.

- [ ] **Step 5: Commit** `feat: pipeline harness + TTS fixtures; E2E verified with real models` (include actual harness outputs in the commit body).

---

### Task 11: AudioCaptureService

**Files:** Create `Sources/Ghostwriter/AudioCaptureService.swift`; Modify `Sources/Ghostwriter/main.swift` (temporary debug hook, removed in Task 15)

**Interfaces:**
- Produces (consumed by Task 15): `final class AudioCaptureService { var onLevel: ((Float) -> Void)?; func start() throws; func stop() -> [Float]; func cancel() }` — 16 kHz mono Float32 samples, `onLevel` called ~30 Hz with RMS 0…1.

- [ ] **Step 1: Implement**

```swift
import AVFoundation

/// Captures mic audio as 16 kHz mono Float32 (Whisper's native format).
/// start() is called on hotkey-down; the engine starts immediately so the
/// first syllable is never clipped (spec §7).
final class AudioCaptureService {
    var onLevel: ((Float) -> Void)?
    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    func start() throws {
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()
        let input = engine.inputNode
        let hwFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: hwFormat, to: Self.targetFormat)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: hwFormat) { [weak self] buffer, _ in
            self?.consume(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    private func consume(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = Self.targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.targetFormat, frameCapacity: capacity) else { return }
        var fed = false
        converter.convert(to: out, error: nil) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return buffer
        }
        guard let ch = out.floatChannelData?[0], out.frameLength > 0 else { return }
        let chunk = Array(UnsafeBufferPointer(start: ch, count: Int(out.frameLength)))
        lock.lock(); samples.append(contentsOf: chunk); lock.unlock()
        let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
        let level = min(1.0, rms * 12)
        DispatchQueue.main.async { [weak self] in self?.onLevel?(level) }
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock(); defer { lock.unlock() }
        return samples
    }

    func cancel() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock(); samples.removeAll(); lock.unlock()
    }
}
```

- [ ] **Step 2: Build; smoke-test by temporary main.swift hook** (record 3s, print sample count ≈ 48000, print max level > 0 when speaking — note: no mic input in agent context; assert only count > 0 with TTS playing via `say "test" &` if mic loopback unavailable, else defer live check to Antoine's run and verify format math by code review). Run `swift build`. Expected: builds clean.
- [ ] **Step 3: Commit** `feat: pre-armed 16kHz mono audio capture with level metering`

---

### Task 12: HotkeyService

**Files:** Create `Sources/Ghostwriter/HotkeyService.swift`

**Interfaces:**
- Produces (consumed by Task 15): `enum HotkeyChoice: String, Codable, CaseIterable { case fn, rightCommand, rightOption }` with `displayName`; `final class HotkeyService { var choice: HotkeyChoice; var onPress: (() -> Void)?; var onRelease: (() -> Void)?; func start(); func stop(); static func hasAccessibilityPermission() -> Bool; static func requestAccessibilityPermission() }`

- [ ] **Step 1: Implement**

```swift
import AppKit
import Carbon.HIToolbox

enum HotkeyChoice: String, Codable, CaseIterable {
    case fn, rightCommand, rightOption
    var displayName: String {
        switch self {
        case .fn: return "Fn (Globe)"
        case .rightCommand: return "Right ⌘"
        case .rightOption: return "Right ⌥"
        }
    }
}

/// Watches modifier-key transitions system-wide via NSEvent global+local monitors.
/// Requires Accessibility trust. Press/release callbacks fire on the main thread.
final class HotkeyService {
    var choice: HotkeyChoice = .fn
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    private var monitors: [Any] = []
    private var isDown = false

    static func hasAccessibilityPermission() -> Bool { AXIsProcessTrusted() }
    static func requestAccessibilityPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    func start() {
        stop()
        let handler: (NSEvent) -> Void = { [weak self] event in self?.handle(event) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler) {
            monitors.append(global)
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handler(event); return event
        }
        if let local { monitors.append(local) }
    }

    func stop() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll(); isDown = false
    }

    private func handle(_ event: NSEvent) {
        let downNow: Bool
        switch choice {
        case .fn:
            downNow = event.modifierFlags.contains(.function)
        case .rightCommand:
            downNow = event.keyCode == kVK_RightCommand && event.modifierFlags.contains(.command)
        case .rightOption:
            downNow = event.keyCode == kVK_RightOption && event.modifierFlags.contains(.option)
        }
        guard downNow != isDown else { return }
        // For right-modifier choices, releases arrive as flagsChanged without the flag —
        // detect release by keyCode match with flag absent.
        if choice != .fn {
            let isOurKey = event.keyCode == (choice == .rightCommand ? kVK_RightCommand : kVK_RightOption)
            guard isOurKey else { return }
        }
        isDown = downNow
        DispatchQueue.main.async { [weak self] in
            downNow ? self?.onPress?() : self?.onRelease?()
        }
    }
}
```
Caveat baked into Onboarding (Task 17): user must set System Settings → Keyboard → "Press 🌐 key to" → **Do Nothing**, or Fn-taps will also trigger the system emoji picker.

- [ ] **Step 2: Build.** `swift build` — expected clean. (kVK_ constants come from Carbon.HIToolbox; they are Int — cast to match `event.keyCode` UInt16: use `UInt16(kVK_RightCommand)`.)
- [ ] **Step 3: Commit** `feat: system-wide hold-to-talk hotkey (Fn / right-modifier)`

---

### Task 13: InsertionService + AppContextService

**Files:** Create `Sources/Ghostwriter/InsertionService.swift`, `Sources/Ghostwriter/AppContextService.swift`

**Interfaces:**
- Consumes: `AppDatabase.mode(forBundleID:)`.
- Produces (consumed by Task 15):
  - `enum InsertionOutcome { case pasted, copiedOnly(reason: String) }`
  - `final class InsertionService { func insert(text: String) -> InsertionOutcome }`
  - `final class AppContextService { init(db: AppDatabase); func snapshotFrontmost() -> (bundleID: String?, mode: CleanupMode) }`

- [ ] **Step 1: Implement**

`InsertionService.swift`:
```swift
import AppKit
import Carbon.HIToolbox

enum InsertionOutcome: Equatable {
    case pasted
    case copiedOnly(reason: String)
}

/// Clipboard-swap paste: save clipboard string, paste dictation via synthetic ⌘V,
/// restore the previous clipboard afterwards (spec §2). Requires Accessibility.
final class InsertionService {
    func insert(text: String) -> InsertionOutcome {
        let pasteboard = NSPasteboard.general
        if IsSecureEventInputEnabled() {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return .copiedOnly(reason: "A secure input field is active — text copied to clipboard instead.")
        }
        let saved = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else {
            return .copiedOnly(reason: "Could not synthesize paste — text is on your clipboard.")
        }
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)

        // Restore the user's clipboard once the paste has been consumed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if let saved {
                pasteboard.clearContents()
                pasteboard.setString(saved, forType: .string)
            }
        }
        return .pasted
    }
}
```

`AppContextService.swift`:
```swift
import AppKit
import GhostwriterCore

/// Captures the frontmost app at hotkey-down (before our HUD can interfere)
/// and maps it to a cleanup mode via stored profiles (spec §5).
final class AppContextService {
    private let db: AppDatabase
    init(db: AppDatabase) { self.db = db }

    func snapshotFrontmost() -> (bundleID: String?, mode: CleanupMode) {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let mode = (try? db.mode(forBundleID: bundleID)) ?? .lightTouch
        return (bundleID, mode)
    }
}
```

- [ ] **Step 2: Build.** Expected clean.  - [ ] **Step 3: Commit** `feat: clipboard-swap insertion + frontmost-app profile snapshot`

---

### Task 14: Recording HUD

**Files:** Create `Sources/Ghostwriter/HUDController.swift`

**Interfaces:**
- Produces (consumed by Task 15): `@MainActor final class HUDController { func showRecording(); func updateLevel(_ level: Float); func showProcessing(); func flashResult(fallback: Bool); func hide() }`

- [ ] **Step 1: Implement**

```swift
import AppKit
import SwiftUI

@MainActor
final class HUDController {
    private var panel: NSPanel?
    private let model = HUDModel()

    func showRecording() {
        model.phase = .recording
        model.levels = Array(repeating: 0.05, count: HUDModel.barCount)
        presentPanel()
    }
    func updateLevel(_ level: Float) {
        guard model.phase == .recording else { return }
        model.levels.removeFirst()
        model.levels.append(max(0.05, min(1, level)))
    }
    func showProcessing() { model.phase = .processing }
    func flashResult(fallback: Bool) {
        model.phase = fallback ? .doneRaw : .done
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.hide() }
    }
    func hide() { panel?.orderOut(nil); panel = nil }

    private func presentPanel() {
        if panel != nil { return }
        let host = NSHostingView(rootView: HUDView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 220, height: 44)
        let p = NSPanel(contentRect: host.frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = host
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.midX - 110, y: f.minY + 80))
        }
        p.orderFrontRegardless()
        panel = p
    }
}

@MainActor
final class HUDModel: ObservableObject {
    static let barCount = 24
    enum Phase { case recording, processing, done, doneRaw }
    @Published var phase: Phase = .recording
    @Published var levels: [Float] = Array(repeating: 0.05, count: barCount)
}

struct HUDView: View {
    @ObservedObject var model: HUDModel
    var body: some View {
        HStack(spacing: 8) {
            Text("👻").font(.system(size: 18))
            switch model.phase {
            case .recording:
                HStack(spacing: 2) {
                    ForEach(Array(model.levels.enumerated()), id: \.offset) { _, level in
                        Capsule().fill(.white.opacity(0.9))
                            .frame(width: 3, height: CGFloat(6 + level * 22))
                    }
                }
                .animation(.linear(duration: 0.05), value: model.levels)
            case .processing:
                ProgressView().controlSize(.small).tint(.white)
                Text("Transcribing…").font(.caption).foregroundStyle(.white.opacity(0.85))
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .doneRaw:
                Image(systemName: "checkmark.circle").foregroundStyle(.yellow)
                Text("verbatim").font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(width: 220, height: 44)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
    }
}
```

- [ ] **Step 2: Build.** Expected clean.  - [ ] **Step 3: Commit** `feat: floating recording HUD with live waveform`

---

### Task 15: DictationController + app shell (menu bar)

**Files:** Create `Sources/Ghostwriter/AppState.swift`, `Sources/Ghostwriter/DictationController.swift`, `Sources/Ghostwriter/StatusItemController.swift`, `Sources/Ghostwriter/AppDelegate.swift`; Rewrite `Sources/Ghostwriter/main.swift`

**Interfaces:**
- Consumes: every service from Tasks 6–14.
- Produces: running menu-bar app. `AppState` (shared, `@MainActor`): `db: AppDatabase`, `transcriber`, `cleaner`, `settings` (UserDefaults-backed: hotkey, guardrailThreshold, isPaused, hasOnboarded), `historyChanged` notification name `Notification.Name.gwHistoryChanged`. `DictationController.start()` wires hotkey→capture→pipeline→insert→persist.

- [ ] **Step 1: AppState.swift**

```swift
import Foundation
import GhostwriterCore
import GhostwriterML

@MainActor
final class AppState {
    static let shared = AppState()
    let db: AppDatabase
    let transcriber = WhisperTranscriber()
    let cleaner = LlamaServerCleaner()

    private let defaults = UserDefaults.standard

    var hotkey: HotkeyChoice {
        get { HotkeyChoice(rawValue: defaults.string(forKey: "hotkey") ?? "fn") ?? .fn }
        set { defaults.set(newValue.rawValue, forKey: "hotkey") }
    }
    var guardrailThreshold: Double {
        get { defaults.object(forKey: "guardrailThreshold") as? Double ?? 0.15 }
        set { defaults.set(newValue, forKey: "guardrailThreshold") }
    }
    var isPaused: Bool {
        get { defaults.bool(forKey: "isPaused") }
        set { defaults.set(newValue, forKey: "isPaused") }
    }
    var hasOnboarded: Bool {
        get { defaults.bool(forKey: "hasOnboarded") }
        set { defaults.set(newValue, forKey: "hasOnboarded") }
    }

    private init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Ghostwriter")
        db = try! AppDatabase(path: dir.appendingPathComponent("ghostwriter.sqlite").path)
    }
}

extension Notification.Name {
    static let gwHistoryChanged = Notification.Name("gwHistoryChanged")
}
```

- [ ] **Step 2: DictationController.swift**

```swift
import AppKit
import GhostwriterCore

/// The state machine: idle -> recording -> processing -> idle.
/// Press starts capture instantly; release under 0.25s cancels (accidental tap).
@MainActor
final class DictationController {
    private let state = AppState.shared
    private let hotkey = HotkeyService()
    private let audio = AudioCaptureService()
    private let hud = HUDController()
    private let insertion = InsertionService()
    private lazy var appContext = AppContextService(db: state.db)

    private var recordingStart: Date?
    private var snapshot: (bundleID: String?, mode: CleanupMode) = (nil, .lightTouch)
    private var isProcessing = false

    var onStatusChange: ((String) -> Void)?   // feeds the status item tooltip/menu

    func start() {
        hotkey.choice = state.hotkey
        hotkey.onPress = { [weak self] in self?.pressed() }
        hotkey.onRelease = { [weak self] in self?.released() }
        hotkey.start()
        audio.onLevel = { [weak self] level in self?.hud.updateLevel(level) }
        Task { try? await state.transcriber.preload() }          // warm STT at launch
        Task { try? await state.cleaner.ensureRunning(readyTimeout: 600) } // warm LLM at launch
    }

    func updateHotkey() { hotkey.choice = state.hotkey }

    private func pressed() {
        guard !state.isPaused, !isProcessing, recordingStart == nil else { return }
        snapshot = appContext.snapshotFrontmost()
        do {
            try audio.start()
            recordingStart = Date()
            hud.showRecording()
        } catch {
            notify("Microphone unavailable", body: error.localizedDescription)
        }
    }

    private func released() {
        guard let started = recordingStart else { return }
        recordingStart = nil
        let duration = -started.timeIntervalSinceNow
        if duration < 0.25 { audio.cancel(); hud.hide(); return }
        let samples = audio.stop()
        hud.showProcessing()
        isProcessing = true
        let (bundleID, mode) = snapshot
        Task { [weak self] in
            guard let self else { return }
            let pipeline = DictationPipeline(transcriber: state.transcriber, cleaner: state.cleaner)
            let dictionary = (try? state.db.allTerms()) ?? []
            let result = await pipeline.process(audio: samples, mode: mode,
                                                dictionary: dictionary,
                                                guardrailThreshold: state.guardrailThreshold)
            self.finish(result: result, bundleID: bundleID, duration: duration)
        }
    }

    private func finish(result: PipelineResult, bundleID: String?, duration: TimeInterval) {
        isProcessing = false
        if let err = result.errorDescription {
            hud.hide(); notify("Dictation failed", body: err); return
        }
        guard !result.finalText.isEmpty else { hud.hide(); return }

        let outcome = insertion.insert(text: result.finalText)
        hud.flashResult(fallback: result.usedFallback)
        if case .copiedOnly(let reason) = outcome { notify("Copied instead", body: reason) }

        let rec = DictationRecord(createdAt: Date(), rawText: result.rawText,
                                  cleanedText: result.finalText, appBundleID: bundleID,
                                  durationSec: duration, usedFallback: result.usedFallback,
                                  profileUsed: result.mode.rawValue)
        _ = try? state.db.saveDictation(rec)
        NotificationCenter.default.post(name: .gwHistoryChanged, object: nil)
        onStatusChange?(result.finalText)
    }

    private func notify(_ title: String, body: String) {
        // UNUserNotificationCenter requires a signed bundle; keep it simple and robust:
        let n = NSUserNotification()
        n.title = title; n.informativeText = body
        NSUserNotificationCenter.default.deliver(n)
    }
}
```
(`NSUserNotification` is deprecated but functional and works without notification-permission ceremony; acceptable for v1, noted for v1.1.)

- [ ] **Step 3: StatusItemController.swift**

```swift
import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem!
    private let state = AppState.shared
    var lastDictation: String = ""
    var onOpenMain: (() -> Void)?
    var onTogglePause: (() -> Void)?

    func install() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill",
                                   accessibilityDescription: "Ghostwriter")
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let pauseTitle = state.isPaused ? "Resume Ghostwriter" : "Pause Ghostwriter"
        menu.addItem(withTitle: pauseTitle, action: #selector(togglePause), keyEquivalent: "p").target = self
        if !lastDictation.isEmpty {
            let preview = lastDictation.count > 48 ? String(lastDictation.prefix(48)) + "…" : lastDictation
            let copyItem = NSMenuItem(title: "Copy last: “\(preview)”",
                                      action: #selector(copyLast), keyEquivalent: "")
            copyItem.target = self
            menu.addItem(copyItem)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Ghostwriter…", action: #selector(openMain), keyEquivalent: "o").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Ghostwriter", action: #selector(quit), keyEquivalent: "q").target = self
    }

    @objc private func togglePause() { onTogglePause?() }
    @objc private func copyLast() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastDictation, forType: .string)
    }
    @objc private func openMain() { onOpenMain?() }
    @objc private func quit() { NSApp.terminate(nil) }
}
```

- [ ] **Step 4: AppDelegate.swift + main.swift**

`AppDelegate.swift`:
```swift
import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = StatusItemController()
    private let dictation = DictationController()
    private var mainWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menu-bar only (LSUIElement)
        statusItem.install()
        statusItem.onOpenMain = { [weak self] in self?.showMainWindow() }
        statusItem.onTogglePause = { AppState.shared.isPaused.toggle() }
        dictation.onStatusChange = { [weak self] text in self?.statusItem.lastDictation = text }

        if AppState.shared.hasOnboarded && HotkeyService.hasAccessibilityPermission() {
            dictation.start()
        } else {
            showOnboarding()
        }
    }

    func showMainWindow() {
        if mainWindow == nil {
            let host = NSHostingController(rootView: MainWindow())
            let w = NSWindow(contentViewController: host)
            w.title = "Ghostwriter"
            w.setContentSize(NSSize(width: 720, height: 520))
            w.isReleasedWhenClosed = false
            mainWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let host = NSHostingController(rootView: OnboardingView(onComplete: { [weak self] in
                AppState.shared.hasOnboarded = true
                self?.onboardingWindow?.orderOut(nil)
                self?.dictation.start()
            }))
            let w = NSWindow(contentViewController: host)
            w.title = "Welcome to Ghostwriter"
            w.setContentSize(NSSize(width: 560, height: 560))
            w.isReleasedWhenClosed = false
            onboardingWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    func hotkeyChanged() { dictation.updateHotkey() }
}
```

`main.swift` (replace placeholder):
```swift
import AppKit

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
```
Note: Tasks 16–17 create `MainWindow`/`OnboardingView`; to keep the tree building at this commit, add minimal placeholder views in `UI/MainWindow.swift` and `UI/OnboardingView.swift`:
```swift
import SwiftUI
struct MainWindow: View { var body: some View { Text("Ghostwriter").padding(80) } }
```
```swift
import SwiftUI
struct OnboardingView: View {
    let onComplete: () -> Void
    var body: some View { Button("Continue") { onComplete() }.padding(80) }
}
```

- [ ] **Step 5: Build & run smoke.** `swift build` then `swift run Ghostwriter &` — expected: process runs, menu-bar icon appears (verify via `screencapture -x /tmp/menubar.png` + inspect), no crash in 10s; kill it. From a dev binary, Accessibility/mic permission will not be granted — hotkey does nothing yet; that's expected until Task 18's bundled app.
- [ ] **Step 6: Commit** `feat: menu-bar app shell with dictation state machine`

---### Task 16: Main window — History, Dictionary, Settings

**Files:** Create `Sources/Ghostwriter/UI/HistoryView.swift`, `UI/DictionaryView.swift`, `UI/SettingsView.swift`; Rewrite `UI/MainWindow.swift`

**Interfaces:**
- Consumes: `AppDatabase` (Task 6), `AppState` (Task 15), `.gwHistoryChanged`.
- Produces: full `MainWindow` TabView.

- [ ] **Step 1: MainWindow.swift**

```swift
import SwiftUI

struct MainWindow: View {
    var body: some View {
        TabView {
            HistoryView().tabItem { Label("History", systemImage: "clock") }
            DictionaryView().tabItem { Label("Dictionary", systemImage: "character.book.closed") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}
```

- [ ] **Step 2: HistoryView.swift**

```swift
import SwiftUI
import GhostwriterCore

struct HistoryView: View {
    @State private var query = ""
    @State private var rows: [DictationRecord] = []
    @State private var expanded: Set<Int64> = []

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search dictations…", text: $query)
                .textFieldStyle(.roundedBorder).padding()
                .onChange(of: query) { _, _ in reload() }
            List(rows, id: \.id) { rec in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(rec.cleanedText).lineLimit(expanded.contains(rec.id ?? -1) ? nil : 2)
                        Spacer()
                        if rec.usedFallback {
                            Text("verbatim").font(.caption2).padding(3)
                                .background(.yellow.opacity(0.3), in: Capsule())
                                .help("Cleanup overreached; raw transcript was used")
                        }
                        Button { copy(rec.cleanedText) } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless)
                    }
                    HStack(spacing: 8) {
                        Text(rec.createdAt, style: .date).font(.caption2).foregroundStyle(.secondary)
                        Text(rec.createdAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                        if let app = rec.appBundleID {
                            Text(app.split(separator: ".").last.map(String.init) ?? app)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(String(format: "%.1fs", rec.durationSec))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if expanded.contains(rec.id ?? -1) {
                        GroupBox("Raw transcript") {
                            Text(rec.rawText).font(.callout).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { toggle(rec.id) }
                .padding(.vertical, 2)
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .gwHistoryChanged)) { _ in reload() }
    }

    private func toggle(_ id: Int64?) {
        guard let id else { return }
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
    private func copy(_ s: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string)
    }
    private func reload() {
        let db = AppState.shared.db
        rows = (try? (query.isEmpty ? db.recentDictations() : db.searchDictations(query))) ?? []
    }
}
```

- [ ] **Step 3: DictionaryView.swift**

```swift
import SwiftUI
import GhostwriterCore

struct DictionaryView: View {
    @State private var terms: [DictionaryTerm] = []
    @State private var newTerm = ""
    @State private var newAliases = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text("Terms are fed to the speech model so they transcribe correctly. Aliases are common mishearings, auto-corrected to the term.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            HStack {
                TextField("Term (e.g. Supabase)", text: $newTerm).textFieldStyle(.roundedBorder)
                TextField("Aliases, comma-separated (e.g. super base)", text: $newAliases)
                    .textFieldStyle(.roundedBorder)
                Button("Add") { add() }.disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }.padding(.horizontal)
            List(terms, id: \.id) { term in
                HStack {
                    Text(term.term).bold()
                    if !term.aliases.isEmpty {
                        Text("← " + term.aliases.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { remove(term) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical)
        .onAppear(perform: reload)
    }

    private func reload() { terms = (try? AppState.shared.db.allTerms()) ?? [] }
    private func add() {
        let aliases = newAliases.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        try? AppState.shared.db.addTerm(DictionaryTerm(
            term: newTerm.trimmingCharacters(in: .whitespaces), aliases: aliases))
        newTerm = ""; newAliases = ""; reload()
    }
    private func remove(_ term: DictionaryTerm) {
        if let id = term.id { try? AppState.shared.db.deleteTerm(id: id) }
        reload()
    }
}
```

- [ ] **Step 4: SettingsView.swift**

```swift
import SwiftUI
import ServiceManagement
import GhostwriterCore

struct SettingsView: View {
    @State private var hotkey = AppState.shared.hotkey
    @State private var threshold = AppState.shared.guardrailThreshold
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var profiles: [(bundleID: String, mode: CleanupMode)] = []
    @State private var newBundleID = ""
    @State private var newMode: CleanupMode = .verbatimTechnical
    @State private var showAdvanced = false

    var body: some View {
        Form {
            Section("Hotkey") {
                Picker("Hold to dictate:", selection: $hotkey) {
                    ForEach(HotkeyChoice.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .onChange(of: hotkey) { _, v in
                    AppState.shared.hotkey = v
                    (NSApp.delegate as? AppDelegate)?.hotkeyChanged()
                }
                Text("Fn users: set System Settings → Keyboard → “Press 🌐 key to” → Do Nothing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Per-app modes") {
                ForEach(profiles, id: \.bundleID) { p in
                    HStack {
                        Text(p.bundleID)
                        Spacer()
                        Text(p.mode.displayName).foregroundStyle(.secondary)
                        Button { remove(p.bundleID) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Picker("App:", selection: $newBundleID) {
                        Text("Choose running app…").tag("")
                        ForEach(runningApps(), id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Mode:", selection: $newMode) {
                        ForEach(CleanupMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Button("Add") { addProfile() }.disabled(newBundleID.isEmpty)
                }
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in
                        try? v ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
            }
            Section {
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    VStack(alignment: .leading) {
                        Text("Guardrail strictness — how much the cleanup may deviate before Ghostwriter falls back to your exact words. Lower = stricter.")
                            .font(.caption).foregroundStyle(.secondary)
                        Slider(value: $threshold, in: 0.05...0.4, step: 0.05) {
                            Text("Threshold")
                        } minimumValueLabel: { Text("strict") } maximumValueLabel: { Text("loose") }
                        .onChange(of: threshold) { _, v in AppState.shared.guardrailThreshold = v }
                        Text(String(format: "Current: %.2f (default 0.15)", threshold)).font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { profiles = (try? AppState.shared.db.allProfiles()) ?? [] }
    }

    private func runningApps() -> [String] {
        NSWorkspace.shared.runningApplications
            .compactMap(\.bundleIdentifier)
            .filter { !$0.hasPrefix("com.apple.") || $0 == "com.apple.Terminal" || $0 == "com.apple.dt.Xcode" }
            .sorted()
    }
    private func addProfile() {
        try? AppState.shared.db.setMode(newMode, forBundleID: newBundleID)
        profiles = (try? AppState.shared.db.allProfiles()) ?? []
        newBundleID = ""
    }
    private func remove(_ bundleID: String) {
        try? AppState.shared.db.removeProfile(bundleID: bundleID)
        profiles = (try? AppState.shared.db.allProfiles()) ?? []
    }
}
```

- [ ] **Step 5: Build, run, screenshot each tab** (`swift run Ghostwriter`, open main window via menu item programmatically or temporary auto-open; `screencapture -x`). Verify: tabs render, add/remove dictionary term works against the real DB, settings persist across relaunch (check `defaults read` UserDefaults side).
- [ ] **Step 6: Commit** `feat: main window — searchable history, dictionary, settings`

---

### Task 17: Onboarding + ModelManager

**Files:** Create `Sources/Ghostwriter/ModelManager.swift`; Rewrite `Sources/Ghostwriter/UI/OnboardingView.swift`

**Interfaces:**
- Consumes: `WhisperTranscriber.preload`, `LlamaServerCleaner.ensureRunning`, `HotkeyService` permission statics.
- Produces: `@MainActor final class ModelManager: ObservableObject { @Published var status: String; @Published var ready: Bool; func prepareAll() async }` and the stepped `OnboardingView(onComplete:)`.

- [ ] **Step 1: ModelManager.swift**

```swift
import Foundation
import GhostwriterML

@MainActor
final class ModelManager: ObservableObject {
    @Published var status = "Not started"
    @Published var ready = false
    @Published var failed = false

    /// Installs llama.cpp via Homebrew if missing, then downloads/loads both models.
    func prepareAll() async {
        failed = false
        do {
            if !LlamaServerCleaner.binaryExists() {
                status = "Installing llama.cpp via Homebrew…"
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
                p.arguments = ["install", "llama.cpp"]
                try p.run(); p.waitUntilExit()
                guard p.terminationStatus == 0, LlamaServerCleaner.binaryExists() else {
                    throw NSError(domain: "Ghostwriter", code: 5, userInfo: [NSLocalizedDescriptionKey:
                        "Homebrew install failed — run `brew install llama.cpp` in Terminal, then retry."])
                }
            }
            status = "Downloading speech model (one-time, ~1.6 GB)…"
            try await AppState.shared.transcriber.preload { [weak self] s in
                Task { @MainActor in self?.status = s }
            }
            status = "Downloading cleanup model (one-time, ~2.4 GB)…"
            try await AppState.shared.cleaner.ensureRunning(readyTimeout: 3600) { [weak self] s in
                Task { @MainActor in self?.status = s }
            }
            status = "All models ready."
            ready = true
        } catch {
            status = "Setup failed: \(error.localizedDescription)"
            failed = true
        }
    }
}
```

- [ ] **Step 2: OnboardingView.swift** — five steps in a `TabView`-free manual pager:

```swift
import SwiftUI
import AVFoundation

struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var step = 0
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var axGranted = HotkeyService.hasAccessibilityPermission()
    @StateObject private var models = ModelManager()
    @State private var axTimer: Timer?

    var body: some View {
        VStack(spacing: 20) {
            Text("👻").font(.system(size: 56))
            switch step {
            case 0: welcome
            case 1: microphone
            case 2: accessibility
            case 3: globeKey
            case 4: modelSetup
            default: tryIt
            }
            Spacer()
        }
        .padding(32)
        .frame(width: 560, height: 560)
    }

    private var welcome: some View {
        VStack(spacing: 12) {
            Text("Welcome to Ghostwriter").font(.title.bold())
            Text("Hold a key, speak, release — your words appear, cleaned up but never rewritten. Everything runs on this Mac. Nothing is uploaded, ever.")
                .multilineTextAlignment(.center)
            Button("Set up (about 10 minutes, one time)") { step = 1 }
                .buttonStyle(.borderedProminent)
        }
    }
    private var microphone: some View {
        VStack(spacing: 12) {
            Text("Microphone access").font(.title2.bold())
            Text("Ghostwriter needs the mic to hear you. Audio is processed locally and never stored.")
            Button(micGranted ? "✓ Granted" : "Allow microphone") {
                AVCaptureDevice.requestAccess(for: .audio) { ok in
                    DispatchQueue.main.async { micGranted = ok; if ok { step = 2 } }
                }
            }.buttonStyle(.borderedProminent).disabled(micGranted)
            if micGranted { Button("Continue") { step = 2 } }
        }
    }
    private var accessibility: some View {
        VStack(spacing: 12) {
            Text("Accessibility access").font(.title2.bold())
            Text("This lets Ghostwriter notice your hotkey in any app and type the result at your cursor — the same permission other dictation apps use. macOS will open System Settings; enable Ghostwriter, then come back.")
            Button(axGranted ? "✓ Granted" : "Open System Settings") {
                HotkeyService.requestAccessibilityPermission()
                axTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    if HotkeyService.hasAccessibilityPermission() {
                        axGranted = true; axTimer?.invalidate()
                    }
                }
            }.buttonStyle(.borderedProminent).disabled(axGranted)
            if axGranted { Button("Continue") { step = 3 } }
        }
    }
    private var globeKey: some View {
        VStack(spacing: 12) {
            Text("One macOS setting").font(.title2.bold())
            Text("So holding Fn doesn't also open the emoji picker:\n\nSystem Settings → Keyboard → “Press 🌐 key to” → **Do Nothing**")
                .multilineTextAlignment(.center)
            Button("Open Keyboard Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
            }
            Button("Done — continue") { step = 4; Task { await models.prepareAll() } }
                .buttonStyle(.borderedProminent)
        }
    }
    private var modelSetup: some View {
        VStack(spacing: 12) {
            Text("Downloading your models").font(.title2.bold())
            Text("Two one-time downloads (~4 GB total). After this, Ghostwriter is fully offline and free forever.")
                .multilineTextAlignment(.center)
            ProgressView().opacity(models.ready || models.failed ? 0 : 1)
            Text(models.status).font(.callout).foregroundStyle(models.failed ? .red : .secondary)
            if models.failed { Button("Retry") { Task { await models.prepareAll() } } }
            if models.ready { Button("Continue") { step = 5 }.buttonStyle(.borderedProminent) }
        }
    }
    private var tryIt: some View {
        VStack(spacing: 12) {
            Text("Try it!").font(.title2.bold())
            Text("Click into the box below, hold **Fn**, say something like “um, hello Ghostwriter, this is, uh, my first dictation”, and release.")
                .multilineTextAlignment(.center)
            TextEditor(text: .constant("")).frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.4)))
            Button("Finish setup") { onComplete() }.buttonStyle(.borderedProminent)
        }
    }
}
```
Note: the try-it step requires dictation to be live before `onComplete` — in `AppDelegate.showOnboarding`, call `dictation.start()` when onboarding reaches ready state; simplest correct wiring: `OnboardingView`'s "Continue" on the model step invokes `onComplete` logic that starts dictation but keeps the window open at the try-it step. Implementer: move `dictation.start()` to fire at the try-it transition via a second closure `onReadyToTest`, keeping `onComplete` for final dismissal.

- [ ] **Step 3: Build + walk the onboarding UI** with `swift run Ghostwriter` (permissions may already be granted to the terminal context; verify each pane renders via screenshots).
- [ ] **Step 4: Commit** `feat: onboarding walkthrough + model manager`

---

### Task 18: App bundle, README, final verification

**Files:** Create `Scripts/make_app.sh`, `README.md`

**Interfaces:** Produces `dist/Ghostwriter.app` and user docs.

- [ ] **Step 1: Scripts/make_app.sh** (chmod +x)

```bash
#!/bin/bash
# Builds Ghostwriter.app from the SwiftPM binary (no Xcode required).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP=dist/Ghostwriter.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Ghostwriter "$APP/Contents/MacOS/Ghostwriter"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Ghostwriter</string>
    <key>CFBundleIdentifier</key><string>com.antoine.ghostwriter</string>
    <key>CFBundleName</key><string>Ghostwriter</string>
    <key>CFBundleDisplayName</key><string>Ghostwriter</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Ghostwriter listens while you hold the dictation key. Audio never leaves this Mac.</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 Antoine Tramble</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built: $APP"
echo "NOTE: ad-hoc signature — rebuilding resets Accessibility permission; re-grant after each rebuild."
```

- [ ] **Step 2: README.md** — cover: what it is, one-line install (`./Scripts/make_app.sh && open dist`), drag to /Applications, first-run walkthrough, the Fn/🌐 setting, the ad-hoc-signing re-grant caveat, `swift test` + harness usage, architecture map (one paragraph pointing at the spec/plan), troubleshooting (llama-server log path, model cache paths, secure-input fallback).

- [ ] **Step 3: Full verification pass (the evidence, per global CLAUDE.md):**

```bash
swift test                                             # all Core tests green
swift run -c release ghostwriter-harness Fixtures/basic.wav        # E2E still good
./Scripts/make_app.sh                                  # bundle builds
open dist/Ghostwriter.app                              # launches; menu-bar icon appears
screencapture -x /tmp/gw_final.png                     # visual evidence
```
Record each command's actual output. The bundled app's mic/AX permission grant + live-mic dictation is **Antoine's acceptance run** — write exact steps for him in the README and the handoff message.

- [ ] **Step 4: Commit** `feat: app bundle build script + README` — then `git tag v1.0.0`.

- [ ] **Step 5: Update memory** (`ghostwriter-mission-state.md`): v1 built, what was verified (tests, harness E2E, app launch) vs. claimed (live-mic loop — awaiting Antoine), first command for next session.

---

## Self-review (performed at write time)

- **Spec coverage:** core loop (T11–15), pipeline+guardrail (T2–T10), dictionary (T4, T6, T16), history+FTS (T6, T16), HUD (T14), per-app (T6, T13, T16), onboarding+models (T17), settings incl. threshold+hotkey+login item (T16), error handling (T7 fallbacks, T13 secure-input, T9 server-death, T17 retry), testing (T2–T7 unit, T10 E2E gate), performance (warm preloads T15, ≤1s target measured T10/T18). Deferred per spec §10: voice commands, streaming insertion, multi-language, iOS.
- **Known deviations, documented:** llama.cpp for MLX (Global Constraints); `NSUserNotification` deprecation accepted for v1; streaming-during-speech simplified to warm full-buffer transcription — latency target still enforced at the T10 gate.
- **Type consistency check:** `Transcriber`/`TextCleaner` signatures identical across T7/T8/T9/T10/T15; `AppDatabase` method names identical across T6/T13/T15/T16; `HotkeyChoice` across T12/T15/T16; `CleanupMode.displayName` defined T5, used T16.
