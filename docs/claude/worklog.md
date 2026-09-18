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

- 2026-09-17 · fix drift-check to accept absolute/relative repo paths (bare-name-only broke the documented `/workspace/foo` usage); label rows by basename · `scripts/plan-contract-drift.sh` · Harness parity — shared plan contract
- 2026-09-17 · Unify plan-doc contract across harnesses — point opencode (`instructions`) and Claude (`core.md`) at `/workspace/PANOPLY-OPTIMIZATION.md`, add read-only `scripts/plan-contract-drift.sh`, record 14-repo baseline · `shared-plan-contract/` · Harness parity — shared plan contract
- 2026-09-17 · Port Phalanx config layer to opencode — 9 subagents (implementer/orchestrator/researcher/verifier + 5 personas) and 3 commands (work/work-loop/assess-stack) translated to `/config/.config/opencode/agent/` + `command/`, verified via `opencode debug config` · `opencode-port/` · Harness parity — opencode
- 2026-01-01 · _EXAMPLE — delete this line_ — wire server-side paging into the records query · `ui/records-list` · Records UX overhaul
