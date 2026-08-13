# CLAUDE.md

Read this before every task. Each rule below exists because breaking it cost real hours on this project.

## Who you are talking to
- Exactly one human: Antoine. Address him as "you". Never invent third people from file paths, account names, or transcripts. The macOS account name on the Intel machine is not the person you are talking to.
- Two machines exist. The Apple Silicon Mac is the dev box. The Intel Mac (macOS Sequoia 15.7.5, build 24G624, Command Line Tools only, no Xcode) is a test rig. Do not develop on the test rig.
- Releases ship from CI (the Build Universal Release workflow) as a universal binary. The test rig's local toolchain is irrelevant to shipping.

## Think in this order, every time
1. Reproduce or read the exact failure text. Quote it.
2. Read the FIRST error line, and any error that repeats across runs. A repeated error outranks a new one.
3. Classify the problem out loud: CODE, DEPENDENCY, ENVIRONMENT, or HARDWARE.
4. Fix at the level of the class. Never fix an ENVIRONMENT problem with a CODE edit.
5. Verify on the target machine. "Build complete" is not verification.
6. Leave the tree clean.

## Verify premises before building on them
- When the operator states a technical premise, check it before acting on it: sw_vers, xcode-select -p, swift --version, uname -m, official docs.
- macOS build number prefixes: 24 = Sequoia 15, 23 = Sonoma 14, 22 = Ventura 13. Never guess hardware age or model.
- Label your statements: CLAIM (assertion), EVIDENCE (what you actually saw), STATUS: VERIFIED, SUPPORTED, or GUESS. If it is a guess, write GUESS.

## Errors you may not ignore
- Any xcrun, SDK, or PlatformPath error means the toolchain is broken or stale. Stop and name it before any code change. Silence on a repeated toolchain error is a failure.
- EXC_ARITHMETIC, EXC_BAD_ACCESS, SIGFPE, SIGSEGV are CPU traps. Swift try/catch cannot catch them. Never propose try/catch for a trap.
- Diagnose crashes from the crash report, never from intuition: newest file in ~/Library/Logs/DiagnosticReports, read exceptionType and the faulting frame first, then speak.
- Known project constraint: WhisperKit does not run transcription on Intel. Any Intel code path must avoid executing it.

## Dependency discipline
- Never downgrade or pin a dependency to route around a toolchain or platform problem without stating the tradeoff and getting an explicit yes first.
- Version pins and engine swaps are architecture decisions. Propose them, do not perform them.

## Git discipline
- Run git status at session start and session end. Report what you see.
- Experiments never live on main. Use a branch or a stash with a descriptive message.
- Never commit or push unless explicitly asked.

## Command discipline
- One command per code block. Never mash two commands onto one line.
- If a command needs a working directory, join cd and the command with && inside the same block.
- After giving a command, wait for its output before planning further steps.

## Honesty about success
- A successful compile is a compile fact, not a product fact. Success is the feature working on the target machine, confirmed by the operator.
- No celebration emojis before the operator confirms the outcome.
- End every risky step with three lines: what was verified, what was not, what could still fail.

## Escalation
- If the fix requires new architecture (new engine, new dependency, a platform split), stop. Present options with tradeoffs and wait for the decision.
- If the same error blocks you twice, say "I am blocked, here is why" instead of trying a third variation.
- Scope creep is a bug: fix what was asked, list everything else as proposals.
