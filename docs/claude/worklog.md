# Worklog

Running record of what actually happened — **one line per meaningful change, written in the SAME
commit as the change.** Continuous / chronological view (`in-progress.md` is current *state*; this is
*history*). Newest first.

> **This file exists only when the repo has no running changelog.** If the repo keeps a `CHANGELOG.md`
> or `HISTORY.md` with an `## [Unreleased]` section, THAT is the worklog — append there and delete this
> file. Never keep two parallel running logs. `/adapt-claude-setup` picks the target and reports which
> one it chose.

A change earns a line when it lands source, config, schema, or shipped docs. Trivial typo / format-only
commits need none. The line is part of the diff, not a follow-up — **shipped-but-unlogged counts as not
done** (`.claude/rules/documentation.md`).

## Format

`- YYYY-MM-DD · <what changed, imperative> · \`<where: file or area>\` · <initiative / queue-row, if any>`

Append-only, never pruned. On ship: promote the durable entry to `completed-features.md` and move the
`roadmap.md` initiative, in the same commit.

<!-- new lines below, newest first -->

- 2026-09-21 · teach `plan-contract-drift.sh` to check **tracked-ness, not just existence** — the reason this repo passed 13/13 with its entire kit uncommitted. New hard `KIT` column (≥1 tracked `.claude/rules/` module + tracked `scripts/sync-agents.sh`), `UNTRACKED`/`MISSING` states for `AGENTS` and `MIRROR`, and non-fatal `soft:` notes for the three findings that have legitimate exceptions in the fleet (`queue-untracked` — §1a calls the queue a generated view and frame-forge honours that; `settings-untracked`; `gates-not-wired` / `no-ci-workflow` — levio + plexo wire the gates into `ci.yml`, fylo has a recorded do-not-wire decision). Adds `scripts/test-plan-contract-drift.sh` (7 cases, picked up by `scripts/verify.sh`): committed kit conforms, untracked kit is drift, absent kit is MISSING, untracked roadmap still caught, soft notes never fail the run, `CHANGELOG.md` satisfies the worklog column, non-repo path is labelled not crashed. Fleet re-audited: 13/13 conform, exit 0 · `scripts/plan-contract-drift.sh`, `scripts/test-plan-contract-drift.sh` · Harness parity — shared plan contract
- 2026-09-21 · commit this repo's own Panoply kit — **43 files that were untracked on `main`**: `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `CONVENTIONS.md`, `.claude/` (rules ×9, agents ×6, commands ×3, `settings.json`, `settings.local.json.example`), the generated mirrors (`.cursor/rules/` ×10, `.clinerules/`, `.windsurf/`, `.github/copilot-instructions.md`), and the vendored kit scripts (`sync-agents.sh`, `check-docs.sh`, `check-expert-review.sh`, `init-repo-protection.sh`, `templates/ci-verify.yml`, `templates/pre-commit`). `plan-contract-drift.sh` never caught this because it checks existence, not tracked-ness — this repo reported conforming with its whole governance uncommitted, so a fresh clone had none of it. Fixing `check-expert-review.sh` on the way in (dead `reason` variable = SC2034 at the severity `ci.yml` gates on; exit code now explicit instead of relying on `set -e`) diverges phalanx's copy from the upstream kit — backport recorded as a gap · `.claude/`, `AGENTS.md`, `scripts/`, mirrors · Harness parity — shared plan contract
- 2026-09-21 · green the CI `static` job: `phalanx-gc.sh` reported stray loop state with `ls -a | grep -E`, which shellcheck rejects at warning severity (SC2010) and which has failed both `static` matrix legs on every push to `main` since 2026-09-20. Replaced with a glob + `case` in a new `stray_loop_state()` helper — same names reported, no `ls` parsing, safe on filenames with spaces/newlines/leading dashes. Verified: `shellcheck -S warning` clean across every tracked `.sh` + `install.sh`/`uninstall.sh`, `bash -n` clean, `node --check` clean, `scripts/verify.sh` all green · `scripts/phalanx-gc.sh` · Repo hygiene — CI green on `main`
- 2026-09-19 · drop `flutter` from the drift-check fleet list — `/workspace/flutter` is a pristine upstream flutter/flutter clone (branch `stable`, kit landed untracked by mistake), removed from PANOPLY-OPTIMIZATION.md §2 as not a Joeybuilt project · `scripts/plan-contract-drift.sh` · Harness parity — shared plan contract
- 2026-09-17 · fix drift-check to accept absolute/relative repo paths (bare-name-only broke the documented `/workspace/foo` usage); label rows by basename · `scripts/plan-contract-drift.sh` · Harness parity — shared plan contract
- 2026-09-17 · Unify plan-doc contract across harnesses — point opencode (`instructions`) and Claude (`core.md`) at `/workspace/PANOPLY-OPTIMIZATION.md`, add read-only `scripts/plan-contract-drift.sh`, record 14-repo baseline · `shared-plan-contract/` · Harness parity — shared plan contract
- 2026-09-17 · Port Phalanx config layer to opencode — 9 subagents (implementer/orchestrator/researcher/verifier + 5 personas) and 3 commands (work/work-loop/assess-stack) translated to `/config/.config/opencode/agent/` + `command/`, verified via `opencode debug config` · `opencode-port/` · Harness parity — opencode
- 2026-01-01 · _EXAMPLE — delete this line_ — wire server-side paging into the records query · `ui/records-list` · Records UX overhaul
