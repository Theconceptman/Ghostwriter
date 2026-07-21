# Ghostwriter 👻

Hold a key. Speak. Release. Your words appear at the cursor — cleaned up, never
rewritten. A free, fully local replacement for Wispr Flow on macOS.

- **$0 forever.** Speech runs on-device (Whisper large-v3-turbo via WhisperKit on
  the Neural Engine); cleanup runs on a local Qwen3-4B via llama.cpp. The only
  network use is a one-time ~4 GB model download.
- **Your voice stays your voice.** A *fidelity guardrail* diffs every cleanup
  against what you actually said — if the AI rewrote instead of trimmed, Ghostwriter
  silently uses your exact words. Rewriting is structurally impossible.
- **Private.** Audio and transcripts never leave this Mac. History lives in a local
  SQLite file only you can read.

## Install (first time)

```bash
./Scripts/make_app.sh
open dist            # then drag Ghostwriter.app to /Applications
open /Applications/Ghostwriter.app
```

The welcome window walks you through:
1. **Microphone** permission (macOS prompt)
2. **Accessibility** permission (System Settings → Privacy & Security →
   Accessibility → enable Ghostwriter) — this is how it sees your hotkey in any
   app and pastes at your cursor
3. Setting **System Settings → Keyboard → “Press 🌐 key to” → Do Nothing** so
   holding Fn doesn't also open the emoji picker
4. Model downloads (~4 GB, one time; needs `brew` for llama.cpp if not installed)
5. A try-it box for your first dictation

## Daily use

- **Hold Fn** (configurable: right ⌘ / right ⌥ in Settings), talk, release.
- A small floating pill shows a live waveform while it listens.
- Text lands at your cursor in the frontmost app; your old clipboard is restored.
- A yellow **verbatim** flash/badge means the guardrail rejected the AI cleanup
  and used your exact words instead.
- Menu-bar ghost icon: pause/resume, copy last dictation, open the main window
  (History / Dictionary / Settings), quit.

**Dictionary tip:** add the words Whisper mishears — `Supabase`, `useEffect`,
project names — plus their mishearings as aliases ("super base"). Aliases are
fixed deterministically on every dictation, even in raw mode.

**Per-app modes:** terminals and IDEs (Terminal, iTerm, VS Code, Windsurf, Cursor,
Xcode, Warp, Ghostty) default to *Verbatim technical* — cleanup limited to fillers
and punctuation. Everything else gets *Light touch*. Editable in Settings.

## Known caveats (v1)

- **Ad-hoc code signature:** rebuilding the app resets its Accessibility grant —
  re-enable it in System Settings after each rebuild.
- **Password fields:** macOS secure input blocks synthetic paste; Ghostwriter
  leaves the text on your clipboard and notifies you instead.
- Whisper-level glossary biasing is disabled pending a WhisperKit fix
  (`GW_EXPERIMENTAL_PROMPT=1` to re-test); the alias pass + cleanup spelling
  reference cover dictionary accuracy meanwhile.

## Development

```bash
./Scripts/test.sh                 # unit tests (Swift Testing; works with CLT only)
./Scripts/gen_fixtures.sh         # regenerate TTS test audio
swift run -c release ghostwriter-harness Fixtures/basic.wav --warmup
                                  # end-to-end pipeline on a WAV, no mic needed
GW_DB_PATH=/tmp/dev.sqlite swift run Ghostwriter --open-main   # dev run, scratch DB
```

Architecture, decisions, and amendments: `docs/superpowers/specs/`. Implementation
plan: `docs/superpowers/plans/`. Logs: `~/Library/Application Support/Ghostwriter/`
(`llama-server.log`), models in `~/Documents/huggingface` (Whisper) and
`~/Library/Caches/llama.cpp` (Qwen GGUF).

## Troubleshooting

| Symptom | Fix |
|---|---|
| Hotkey does nothing | Re-grant Accessibility (see caveat above); check Pause state in menu |
| “llama-server exited early” | `tail ~/Library/Application\ Support/Ghostwriter/llama-server.log`; `brew reinstall llama.cpp` |
| First dictation slow | Models warm at launch; give it ~30 s after login |
| Cleanup feels too cautious | Settings → Advanced → raise guardrail threshold |
