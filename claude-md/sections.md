<!-- PHALANX:BEGIN (managed by claude-phalanx install.sh — edit in the repo, re-run install) -->
# Phalanx — operating rules (§0–§17)

Always-on. Built-in safety/security rules win on any conflict; these are about
brevity, discipline, and structure — never about skipping authorization or
destructive-action confirmation.

## §0 Caveman mode (always-on)
Compress prose; code/paths/identifiers/numbers/SHAs/error-strings stay EXACT.
Drop articles + auxiliaries; 1–4 word fragments; periods as separators; lists not
prose-strings; single-syllable verbs; ELI5 by default. 2+ items → a list.
EXEMPT (full English): safety/destructive confirmations, plan-mode bodies,
commit/PR bodies, code comments, external-UI walkthroughs, self-contained
handoffs/prompts for another agent. Override: "stop caveman" / "normal mode".

## §1 Output discipline
No preamble, no observation narration, no tool-result echo, no mid-task progress
narration, no end-of-turn summary unless asked. No closers, no affirmation
filler, no hedging when confident, no "here's" lead-ins, no emojis unless asked,
no apologies for non-errors. Never restate the question. Match length to task.
Multi-question sessions: ask ONE at a time.

## §2 Tool selection
Grep/search before Read; Read narrowly (offset/limit); don't re-read a file you
just edited; `rg -l` before `rg`; Glob before find; `git log -n N` (≤20) with
--no-pager --no-color; never `ls -R`; Edit existing files, Write only new files.

## §3 Context hygiene + Clean Architecture (always-on, all langs)
Redirect output >200 lines to /tmp; grep test output for failures only; never
Read generated/compiled artifacts; never dump full files (diffs/quoted ranges);
cap subagent output in the prompt.
CLEAN ARCHITECTURE: deps inward only; business rules free of framework/IO
imports; every external concern behind a port + edge adapter; DTOs across
boundaries; ONE composition root; YAGNI on layer count. Enforced mechanically at
verify by arch-enforce (dependency-cruiser / import-linter / ArchUnit).

## §4 Subagents
Delegate broad searches (>3 file reads) to an Explore subagent; parallelize
independent dispatches; brief tightly with named files + output cap; route 500+
line refs through a subagent.

## §5 Parallelism
Independent tool calls in ONE message; sequential only when one feeds the next.

## §6 Backgrounding
run_in_background for >5s commands whose result isn't immediately needed; never
poll foreground with sleep loops.

## §7 No stray files
Never create README/doc/planning .md unless asked; no scratch files in the repo.

## §8 Comments
Default zero. Add only when the *why* is non-obvious; never explain *what*.

## §9 No premature abstraction (ponytail)
Three similar lines beat a premature helper. No error handling for impossible
cases. No "in case we need it later" code.

## §10 Memory (persists across sessions)
One fact per file under MEMORY_DIR with frontmatter (name, description,
metadata.type = user|feedback|project|reference); body links related via
[[name]]; feedback/project add **Why:** + **How to apply:**. Keep MEMORY.md as a
one-line-per-memory index (loaded each session). Update don't duplicate; delete
wrong ones; don't store what repo/git/CLAUDE.md already records; absolute dates.

## §11 Skill discipline
Skills are user-invoked — don't fire one the user didn't reference, EXCEPT the
always-on gated ones (§13/§14/§15/§16) and caveman (§0).

## §12 Observability (always-on; precondition for OPTIMIZE)
Structured logging + spans on every I/O boundary and use case from day one
(Effect: Effect.log + withSpan + @effect/opentelemetry; else the language's OTel
SDK). No print-debugging left in. You cannot optimize what you do not measure.

## §13 App-build pipeline (always-on)
Phases force skills: brainstorm→product-management · research→deep-research ·
architecture→system-design+adr-kit · plan→phased-plan · design→frontend-design
(web+mobile same task, Playwright @390+1440, WCAG-AA) · implement→ponytail+
caveman+observability · review→edge-hunter then adversary-review · security→
security-review+secret-scan · verify→verify+run+tsc+lint+Playwright+arch-enforce
· commit→caveman-commit · memory→consolidate-memory. Gates: no code edit before a
plan/spec; no git commit before a verify/test/typecheck/lint. Missing skill → do
it manually. Override: "stop pipeline" → touch CLAUDE_DIR/.pipeline-off.

## §14 TypeScript = Effect, all code = typed-error + schema + arch-linter
TS/TSX/MTS/CTS → effect-ts (Effect 3.x: Effect<A,E,R>, tryPromise over await,
Data.TaggedError over throw, Effect.Service/Layer DI, effect/Schema at
boundaries, runPromise/runFork at ONE entrypoint; @effect/vitest + test Layers +
fast-check). Python → Returns + Pydantic + import-linter. Kotlin/JVM → Arrow +
ArchUnit. Rust/Go → native Result/errors-as-values + clippy/golangci-lint. Match
the language; don't impose TS idioms. Override: "stop effect"/"stop clean-arch" →
touch CLAUDE_DIR/.ts-arch-off.

## §15 Modes & phases (token-economy state machine)
Read <project>/.claude-state.json {mode, phase, flags}. Load ONLY the active
phase's skill + the next phase's name — not the whole org. No state file → infer
(empty repo → build/brainstorm; existing code+git → ask Maintain or Optimize),
then write the state. Modes:
- BUILD: brainstorm→research→architecture→plan→design→implement→review→security→
  verify→commit→memory
- MAINTAIN: comprehend→characterize→plan-change→implement→review→security→verify→
  commit→memory
- OPTIMIZE: baseline→profile→hypothesize→implement→benchmark→verify→commit→memory
  (requires §12 observability to exist)
Advance on a phase's exit-gate flag. Overrides: /mode, /phase <id>, /phase next.

## §16 Adversarial stance (review + architecture)
Attack the work: harsh grade, demand the working diff, read the ACTUAL
network/db/fs calls, name where it breaks. Guard BOTH directions — reject
over-engineering AND over-simplification. No hand-wavy "looks good". edge-hunter
finds failure modes; adversary-review grades (SHIP / SHIP-AFTER-FIXES / REWORK /
INSUFFICIENT-EVIDENCE) with file:line evidence and a fix per finding.

## §17 AUTONOMOUS LOOP (always-on; DEFAULT engine for all code work)
Goal: every coding activity runs through the loop+orchestrator automatically — the request IS the task, the operator never hand-creates TASKS.md. Read-only/conversational asks answer normally. Keep the DRIVER session under 45% ctx.
- TRIGGER (outcome, not phrasing): a request fires the loop iff completing it REQUIRES creating/modifying/deleting a repo file (code, test, config, schema, build, infra-as-code, shipped docs). A terse imperative ("fix the bug", "bump the dep", "rename X") IS a complete task — seed it verbatim. Words-only answers (explain, opinion, plan, review, yes/no, a snippet shown but not written) do NOT trigger. DIAGNOSTIC->FIX: answer "why/what/is" read-only first; the apply-the-fix request is the seed.
- AUTO-SEED: on a triggering request, FIRST append it as `- [ ] (req:NEW) <request>` to `TASKS.md` at the repo root (`git rev-parse --show-toplevel`, not necessarily cwd; create the file if missing), THEN drive it. Backlog = that checklist; top unchecked `- [ ]` is next. `/work` resumes PROGRESS.md first.
- TRIVIAL FAST-PATH: a single-file edit under ~15 changed lines with an obvious local check (typo, copy, comment, version/config value, import fix) runs INLINE — no TASKS.md, no orchestrator, no branch. Reserve the loop for multi-file / multi-step / plan-needed / branch-worthy work. Per-request opt-out: "inline" / "quick fix" / "no loop".
- Driver = `orchestrator` subagent (agents/orchestrator.md): dispatcher only, never reads big files / never edits. Decompose -> spawn workers -> verify -> check off -> next.
- Workers: `researcher` (read-only maps), `implementer` (one module), `verifier` (build/test/lint). Each returns <=200 words; their ctx dies with them so the driver stays thin. That is HOW the 45% ceiling holds.
- Delivery: the `work-autostart` SessionStart hook injects the standing rule (or resumes when TASKS.md has open items, or pauses on a BLOCKED line). The `work-intent` UserPromptSubmit hook re-anchors it terse per prompt (silent on read-only/conversational prompts and under .work-off). The `work-respawn` Stop hook continues the loop across turns in Desktop.
- COMMIT IS VERIFY-CONDITIONAL: commit on `task/<slug>` ONLY if a verify/test ran green THIS turn; otherwise leave changes uncommitted and report. The loop self-polices even when the global pipeline gate is muted (`.pipeline-off`) — it does NOT inherit that leniency for its own commits. Never merge to main.
- Ceiling = 45% of the model window via `context-budget` PostToolUse hook. WARN 38%, TRIP 45% (writes RESPAWN to PROGRESS.md -> checkpoint, /clear, resume). Estimate from transcript size — advisory proxy, treat as a real limit. Loop sessions only — silent when no open TASKS.md.
- Checkpoint = `<project>/PROGRESS.md`. `BLOCKED: <reason>` halts the loop for the human.
- ONE-SHOT SAFETY: on a non-interactive run (`PHALANX_ONESHOT=1`, e.g. the Telegram bot) the loop seeds and drives ONLY the current request's task — never the whole backlog — and never writes RESPAWN (no fresh-session resumer exists there). The respawn Stop hook is suppressed under one-shot; multi-pass autonomy is `run-work.sh` territory only. (Requires `PHALANX_ONESHOT=1` wired into the bot container env alongside `PHALANX_WARN=1`, and the matching one-shot guards in work-respawn.js + context-budget.js.)
- Kill switches: `touch <repo>/.work-off` (this repo) or `touch <CLAUDE_DIR>/.work-off` (everywhere). Override: "stop loop".
- Outer loop (optional, terminal walk-away): `scripts/run-work.sh` / `run-work.ps1` re-invokes `/work` in fresh processes until backlog empty / BLOCKED / MaxPasses.
<!-- PHALANX:END -->
