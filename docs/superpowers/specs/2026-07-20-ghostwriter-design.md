# Ghostwriter — Design Spec

**Date:** 2026-07-20
**Status:** Approved by Antoine (verbal), pending written-spec review
**Goal:** Replace the Wispr Flow subscription ($15/mo) with a free, local, Mac-native
dictation app that is faster, more private, and — critically — never rewrites what
Antoine actually said.

## 1. Product definition

Ghostwriter is a macOS menu-bar dictation app. The core loop:

1. Hold the hotkey (default **Fn**) in any app.
2. A small floating HUD with a live waveform appears; speak.
3. Release the key.
4. Cleaned-up text appears at the cursor in whatever app is frontmost, in ~1 second.

Everything else in the app exists to support that loop.

### Decisions log (from brainstorming, 2026-07-20)

| Decision | Choice | Why |
|---|---|---|
| Platform scope | macOS first; iPhone is phase 2 | Mac is where vibe coding happens; iOS can't do system-wide insertion anyway |
| STT engine | Local on-device (WhisperKit, Whisper large-v3-turbo) | $0 forever, private, offline; fast on M3 Pro Neural Engine |
| Cleanup aggressiveness | Light touch | Fillers out, punctuation in, self-corrections resolved; **never rephrases** |
| Cleanup brain | Local ~4B instruct model via MLX (Qwen3-4B class, 4-bit) | Antoine's hard constraint: no recurring spend. Restraint enforced by guardrail, not model manners |
| Hotkey | Hold-to-talk (Fn, configurable) | Walkie-talkie feel; release doubles as the "go" signal |
| V1 extras | Personal dictionary, history, recording HUD, per-app awareness | All four approved |
| Stack | Native Swift (SwiftUI + AppKit) | Only path to beating Wispr Flow on feel; base for future iOS sibling |

### Hard constraints

- **$0 running cost.** No API calls, no subscriptions. Network use is limited to
  one-time model downloads.
- **Voice fidelity.** The app must be structurally incapable of substantially
  rewriting the user's words (see Fidelity Guardrail).
- **Privacy.** Audio and transcripts never leave the machine.

## 2. Architecture

A single SwiftUI menu-bar app (LSUIElement) with these components:

| Component | Responsibility | Key tech |
|---|---|---|
| `HotkeyService` | Detect Fn press/release system-wide; configurable key | CGEventTap / NSEvent global monitor (flagsChanged) |
| `AudioCaptureService` | Pre-armed mic capture on key-down; 16 kHz mono buffers | AVAudioEngine |
| `TranscriptionService` | Streaming transcription while speaking; dictionary bias | WhisperKit (large-v3-turbo, CoreML/ANE) |
| `CleanupService` | Light-touch cleanup with per-app profile in prompt | MLX Swift, Qwen3-4B-class 4-bit |
| `FidelityGuardrail` | Diff cleaned vs. raw; fall back to raw if over threshold | Word-level diff, pure Swift, unit-tested |
| `AppContextService` | Identify frontmost app → cleanup profile | NSWorkspace |
| `InsertionService` | Clipboard-swap paste; restore prior clipboard | NSPasteboard + CGEvent (Cmd+V) |
| `HUDController` | Floating non-activating waveform pill during recording | NSPanel |
| `ModelManager` | Download, verify, lazy-load, unload models | URLSession, checksums |
| `PersistenceStore` | History + dictionary + app profiles; full-text search | GRDB (SQLite, FTS5) |
| Main window | History / Dictionary / Settings tabs | SwiftUI |
| Onboarding | Permissions walkthrough + model downloads | SwiftUI |

### Data flow

Key-down → HUD shows + mic starts → audio chunks stream into WhisperKit →
key-up → final transcript assembled → `AppContextService` picks profile →
`CleanupService` produces cleaned text → `FidelityGuardrail` approves or
substitutes raw → `InsertionService` pastes at cursor → dictation saved to
history (raw + cleaned + metadata).

### Data model (SQLite via GRDB)

- **Dictation**: id, createdAt, rawText, cleanedText, appBundleID, durationSec,
  usedFallback (bool), profileUsed
- **DictionaryTerm**: id, term, aliases (optional misheard variants)
- **AppProfile**: bundleID, mode (`verbatimTechnical` | `lightTouch` | custom
  prompt addendum)

Stored in `~/Library/Application Support/Ghostwriter/`. Local only.

## 3. The Fidelity Guardrail (the anti-Wispr-Flow feature)

After cleanup, compare cleaned text to raw transcript at word level:

- Allowed deltas: filler-word removals (from a known list), punctuation,
  capitalization, self-correction eliminations (deleted spans immediately
  preceding a correction marker like "no wait", "I mean", "actually").
- Compute a change ratio over words that are neither fillers nor corrected spans.
- If ratio exceeds threshold (initial: 15%, tunable in Settings under an
  "advanced" disclosure), silently use the raw transcript and mark
  `usedFallback = true` in history so overreach is visible and debuggable.

This makes "never changes too much" a guarantee independent of which cleanup
model is installed. The cleanup model is swappable (any MLX-community instruct
model) precisely because the guardrail, not the model, owns fidelity.

## 4. Personal dictionary

- User adds terms ("Supabase", "Claude Code", "Ghostwriter", …) in the
  Dictionary tab; optional aliases for known mishearings ("super base").
- Terms are injected into Whisper's decoding context (prompt conditioning) to
  bias recognition, and passed to the cleanup prompt for spelling enforcement.
- Alias → term substitution runs as a deterministic post-pass (not LLM),
  so it always works even when cleanup falls back to raw.

## 5. Per-app awareness

`AppContextService` maps frontmost bundle ID → profile:

- Default seeds: Terminal, iTerm2, VS Code/Windsurf/Cursor, Xcode → `verbatimTechnical`
  (cleanup limited to fillers + punctuation; no casual smoothing; dictionary
  spelling strictly enforced).
- Messages, Mail, browsers → `lightTouch` (default behavior).
- Users can add/edit rules in Settings. Unknown apps get `lightTouch`.

## 6. UX surfaces

- **Menu bar:** ghost icon; dropdown with pause/resume, last dictation
  (click to re-copy), open main window, quit.
- **HUD:** small floating pill, bottom-center of the active screen, live
  waveform, appears on key-down, never steals focus.
- **Main window tabs:**
  - *History* — searchable (FTS), each row shows cleaned text, expandable to
    raw + metadata (app, duration, fallback flag); copy buttons.
  - *Dictionary* — add/remove terms and aliases.
  - *Settings* — hotkey picker, per-app rules, model management, guardrail
    threshold (advanced), launch-at-login.
- **Onboarding (first run):** explains and requests Microphone +
  Accessibility (and Input Monitoring if macOS requires it for the event tap),
  then downloads models (~4 GB total) with progress; ends with a "try it here"
  practice text field.

## 7. Performance targets

- Release-to-text: **≤ 1s** for a typical (≤ 10s) utterance. Achieved by
  streaming transcription during speech + fast 4B cleanup on short text.
- First syllable never clipped (mic pre-arms on key-down).
- Idle footprint: models lazy-loaded on first dictation of a session;
  unloaded after configurable idle period (default 10 min). Idle RAM target
  ≤ 150 MB with models unloaded.
- Runs comfortably on 18 GB M3 Pro (Whisper turbo ~1.5 GB + 4B LLM ~2.5 GB
  when hot).

## 8. Error handling

- Cleanup model error/timeout → raw transcript (never nothing), fallback flagged.
- Insertion blocked (secure input fields) → text stays on clipboard +
  user notification.
- Model files missing/corrupt → guided re-download; app stays functional for
  raw-only dictation if only the cleanup model is missing.
- Mic permission revoked → menu-bar state + reopen onboarding step.
- Clipboard restore is guaranteed (restore on defer, even after paste failure).

## 9. Testing & verification

- Unit tests: FidelityGuardrail (fixture pairs raw/cleaned, both accept and
  fallback cases), alias substitution, dictionary prompt injection, clipboard
  save/restore logic, hotkey state machine.
- **Pipeline harness:** a debug CLI target that feeds recorded WAV files
  through the exact production pipeline (transcribe → clean → guardrail),
  printing raw/cleaned/fallback — used for end-to-end verification without a
  live mic.
- Live-mic verification is Antoine's: per his global rules, "done" means he has
  held the key, spoken, and watched correct text land in a real app (including
  Claude Code / a terminal).

## 10. Phasing

- **V1 (this spec):** core loop, HUD, history, dictionary, per-app profiles,
  onboarding, settings.
- **V1.1+ (deferred, not designed here):** voice commands ("new line",
  "scratch that"), streaming word-by-word insertion, multi-language,
  auto-learning dictionary from corrections.
- **Phase 2 (separate spec):** iPhone 16 Pro Max sibling (custom keyboard or
  share-sheet app), reusing the Swift transcription/cleanup core.

## 11. Out of scope

- Any cloud STT/LLM, accounts, telemetry, or payments.
- Windows/Linux.
- Real-time translation.

## Amendment — 2026-07-20 (environment-forced substitutions)

Antoine's machine has Command Line Tools only (no full Xcode; installing it
needs his Apple ID and ~40 GB of the ~19 GB free disk). Two substitutions,
both preserving every hard constraint (local, $0, private, swappable):

1. **Cleanup engine: llama.cpp instead of MLX.** MLX requires Xcode's Metal
   build toolchain; llama.cpp compiles its Metal kernels at runtime and
   installs via Homebrew. Cleanup model: Qwen3-4B-Instruct-2507 GGUF Q4_K_M
   (~2.4 GB) served by a Ghostwriter-managed local `llama-server` subprocess.
   Any GGUF model can be swapped in later.
2. **Tests: Swift Testing instead of XCTest.** CLT ships `Testing.framework`
   but not XCTest; `Scripts/test.sh` supplies the framework search path.

Resolved toolchain (verified building 2026-07-20): Swift 6.2.3, WhisperKit
0.18.0, GRDB 6.29.3, macOS 26.1.

3. **Whisper prompt conditioning disabled.** WhisperKit 0.18's `promptTokens`
   path returns empty transcripts for large-v3-turbo (immediate EOT with
   correctly encoded tokens; reproduced 2026-07-20 with and without timestamp
   suppression). Spec §4's dictionary therefore relies on its other two layers —
   deterministic alias substitution and the cleanup model's spelling
   reference — which the E2E gate verified working ("use effect" → "useEffect").
   Re-test on WhisperKit upgrades via `GW_EXPERIMENTAL_PROMPT=1`.
