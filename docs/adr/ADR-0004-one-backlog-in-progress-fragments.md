# ADR-0004 — One backlog: `docs/claude/in-progress.d/` fragments

- **Status:** Accepted (2026-08-30)
- **Deciders:** Operator, Phalanx maintainer, Panoply maintainer
- **Relates to:** [ADR-0003](ADR-0003-worktree-isolation.md); Panoply `.claude/rules/documentation.md`

## Context

One project, three backlogs, and no agreement between them.

- **Panoply** declares the tactical queue to be `docs/claude/in-progress.md` — "always read this first" — updated in the same change that lands work. It is committed, so it is the only one a reviewer, a diff, or a non-Claude agent can see. It says nothing about `TASKS.md`; the string appears nowhere in the kit.
- **Phalanx** (§17) declares the backlog to be `TASKS.md` at the repo root: `- [ ] (req:NEW) <request>`, top unchecked item is next. It is deliberately untracked, so it is invisible to review, to GitHub, and to every agent that is not this loop.
- **OpenCode** keeps its own session database, which neither of the above can read.

The result is that "what is next" has three answers. A task seeded into `TASKS.md` is invisible to the human reading `in-progress.md`; a task written into `in-progress.md` never gets driven, because the loop does not look there. Work is duplicated, and each surface makes the other two look stale.

Neither system is wrong about its own half. Panoply is right that the backlog must be committed — an untracked queue cannot be reviewed, cannot survive a fresh clone, and cannot be read by a tool that is not Claude Code. Phalanx is right that a driver needs machine-readable state — status, request scoping, a risk flag, an ordering — which a prose table does not reliably give.

## Decision

**`docs/claude/in-progress.d/<slug>.md` is the single backlog.** One file per task, committed to the repo. Both systems read and write it; `TASKS.md` is retired.

1. **One file per task, never a shared table.** Two concurrent branches must never collide on a queue file — the same reason Panoply moved the worklog to `.changeset/` fragments. The rendered table (`pnpm queue` → `docs/claude/in-progress.md`) is a generated view, not committed, and never hand-edited.

2. **The fragment carries frontmatter the loop can drive.** Prose alone cannot be dispatched:

   ```markdown
   ---
   id: <slug>
   status: open | in-progress | blocked | done
   order: <int>          # optional; ties break by filename
   req: <request-id>     # optional; set by a request-scoped seed
   risk: operator-confirm  # optional; the operator-risk HALT flag
   ---

   <what the task is>

   **Next step:** <the exact next action — file, function, command, blocker>
   ```

   `status` replaces the `- [ ]` checkbox. `req:` replaces the `(req:<id>)` tag. `risk:` replaces scanning prose for a risk flag. `Next step:` is the same handoff line both systems already require.

3. **Phalanx reads and writes fragments.** `ts_has_open` (and its JS mirror `tasksState`) becomes "at least one fragment with `status: open` or `status: in-progress`". `seed-task.sh` writes a fragment; `unseed-task.sh` deletes the one matching `req:`; the orchestrator's check-off sets `status: done` (and deletes the fragment on ship, per the Panoply contract). Resolution still goes through `git rev-parse --git-common-dir`, so ADR-0003's shared-state guarantee is unchanged.

4. **`TASKS.md` is a fallback, not a home.** If a repo has no `in-progress.d/` but does have `TASKS.md`, the loop reads `TASKS.md` exactly as it does today. This is a migration shim so an unmigrated repo keeps working; nothing new is ever written to it.

5. **`PROGRESS.md` stays, and is not a backlog.** It is the current run's checkpoint and the home of the `BLOCKED:` halt directive. The durable next step is mirrored into the fragment on pause, so a cold session that has only the repo — no `.claude-runs/`, no untracked files — can still resume.

## Consequences

- The backlog lands in the diff. A reviewer sees the queue change alongside the code, and the loop's work stops being invisible to everyone who is not running the loop.
- OpenCode, Plexo, Cursor, and any other agent get the same queue for free: it is committed markdown at a path the kit already names in every provider mirror.
- Panoply's same-change contract and Phalanx's auto-seed become the same act, so a task can no longer exist in one system and not the other.
- Cost: roughly twenty files across `sh` and `js` reference `TASKS.md`, plus the orchestrator prompt and the `claude-md/sections.md` §17 text. Detection already funnels through `scripts/tasks-state.sh` and `hooks/gates/lib/phalanx-hook.js`; the writes (`seed-task.sh`, `unseed-task.sh`, check-off) do not, and each needs its own change.
- A committed backlog is a public one. A task whose text should not be in a repo does not belong in `TASKS.md` either — the fix is to write the task without the secret, not to keep an untracked queue.

## Verification

Not yet implemented — this ADR is the decision, and the sweep is the next change. It is done when:

- `install.sh` self-tests cover: a fragment backlog is detected as open; a `status: done` fragment is not; `seed-task.sh` creates a fragment and `unseed-task.sh` removes exactly the `req:`-matching one; a repo with only `TASKS.md` still drives (rule 4).
- No script or hook writes `TASKS.md`.
- `claude-md/sections.md` §17 names `in-progress.d/`, and Panoply's `.claude/rules/documentation.md` names the same frontmatter keys, so the two contracts cannot drift.
