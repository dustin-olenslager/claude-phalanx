# claude-phalanx — Claude Code Guidelines

## Project Overview

Turn Claude Code into a phase-aware, multi-team software factory: a hard-gated pipeline,
Clean Architecture + Effect standards, adversarial review, and token discipline — all
always-on and enforced by hooks, so they survive every session and apply to subagents.

**Core pillars**: hard-gated pipeline (no code before a plan, no commit before a verify);
always-on standards enforced by hooks, not memory; adversarial review that demands a working
diff per finding; token economy — only the active phase's team is on the clock.

## Tech Stack

- **Language / runtime**: Bash + Node.js 22 (CI-pinned; gates in `.js`, helpers in `.mjs`)
- **Package manager**: none — bare scripts, no manifest
- **Server**: none — this repo is the orchestration tool itself, not a service runtime

## Key Commands

| Purpose | Command |
|---|---|
| Install | `bash ./install.sh` |
| Test | `bash scripts/verify.sh` |
| Typecheck / static analysis | `find hooks -name '*.js' -print0 \| xargs -0 -n1 node --check && find scripts -name '*.mjs' -print0 \| xargs -0 -n1 node --check && find scripts hooks -name '*.sh' -print0 \| xargs -0 -n1 bash -n` |
| Lint | `find scripts hooks -name '*.sh' -print0 \| xargs -0 shellcheck -S warning && shellcheck -S warning install.sh uninstall.sh` |

Every command in this table must actually exist in the project's script table. If one doesn't, the
model will confidently run a command that fails — delete the row instead.

## Project Structure

```
install.sh / install.ps1      installer + embedded self-test; merges into CLAUDE_DIR, never clobbers
uninstall.sh                  removes the installed Phalanx
scripts/                      the loop + tooling: run-work.sh (supervisor), seed-task.sh,
                              supervisord.sh, verify.sh + test-*.sh suites, bot-handoff.sh
hooks/                        installed Claude hooks: gates/ (PreToolUse/PostToolUse .js),
                              anchors/ (SessionStart .sh), lib/ (shared primitives)
githooks/                     pre-commit (leak guard) + pre-push, wired via install-guards.sh
claude-md/                    the §0–§17 operating-rules block merged into installed CLAUDE.md
agents/ commands/ skills/     loop subagents, slash-commands, and skills shipped to CLAUDE_DIR
settings/ policy/ state/      settings fragment, policy contract, mode/phase state templates
configs/                      templates for downstream repos (.dependency-cruiser.js)
docs/                         ADRs (docs/adr/) + this knowledge base (docs/claude/)
```

## How We Work Together

The rules below are not suggestions. When a rule and a shortcut conflict, the rule wins — or you
raise the conflict explicitly and let me decide. Read the module that governs what you're touching
before you touch it.

<!-- Cross-tool agents (Codex, Cursor, Gemini, Copilot, Windsurf, Cline, aider): the provider-neutral
     hub is AGENTS.md at the repo root — read it first. Claude loads it via the import below, so the
     onboarding contract, the non-negotiables, and the hard guardrails are in every Claude context too. -->
@AGENTS.md

### Architecture — the premise everything else inherits from

**Clean Architecture is the premise of all coding efforts in this project.** Business rules live in
the core; the database, the web framework, the UI, and every vendor are replaceable details at the
edge; source-code dependencies point inward only. Every other rules module below is an application
of this premise to its own subject.

@.claude/rules/clean-architecture.md

### Process — how changes get proposed, planned, and landed
@.claude/rules/workflow.md
@.claude/rules/quality-bar.md
@.claude/rules/git-workflow.md
@.claude/rules/documentation.md

### Code — style, tests, failure handling
@.claude/rules/code-style.md
@.claude/rules/testing.md
@.claude/rules/error-handling.md

### AI features — model calls, prompts, enrichment
@.claude/rules/ai-features.md

## Project Knowledge

Team-shared context lives in `docs/claude/` and is committed to git. **Read these when relevant:**

- `docs/claude/roadmap.md` — **the overall plan** — initiatives (Now/Next/Later); read with in-progress.md
- `docs/claude/in-progress.md` — **start here** — the ordered queue of what's next, with pointers to plan docs
- `docs/claude/completed-features.md` — what's already been built
- `docs/claude/worklog.md` — running change log; append one line in the same commit as your change
- `docs/claude/architecture.md` — key decisions and why they were made
- `docs/claude/infrastructure.md` — deploy pipeline, hosting, data stores, jobs
- `docs/claude/key-patterns.md` — dev patterns, gotchas, testing conventions

Personal preferences and per-user workflow rules stay in local `~/.claude/` memory, not here.

## Project-Specific Rules

<!-- Everything above is portable across projects. Everything below is yours alone: the invariant
     that isn't obvious from the code, the integration that breaks in a surprising way, the
     convention a new contributor gets wrong every time. Add rules here as you catch yourself
     correcting the same mistake twice — that repetition is the signal that a rule is missing. -->

- **This repo IS claude-phalanx.** The §0–§17 operating rules live in `claude-md/sections.md` as a
  managed block. Edit there, then re-run `bash ./install.sh` to propagate — never hand-edit an
  installed CLAUDE.md's PHALANX block, and never edit the block's copy in someone else's repo.
- **Verify before commit: `bash scripts/verify.sh`** (bash syntax + all `test-*.sh` suites), plus
  the static gates in CI (`node --check` on `hooks/*.js` and `scripts/*.mjs`, `bash -n` on all
  `*.sh`, shellcheck). No commit without a green `verify.sh`.
- **Hooks and skills are shipped from this repo.** A fix to a gate/anchor/skill is a repo change,
  not a hand-edit in an installed `CLAUDE_DIR`; install.sh copies the tree, so edits propagate on
  re-install.
