# ADR-0003 — Worktree isolation for autonomous passes

- **Status:** Accepted (2026-06-27)
- **Deciders:** Operator, Phalanx maintainer
- **Relates to:** [ADR-0001](ADR-0001-autonomous-merge-deploy-on-green.md), [ADR-0002](ADR-0002-merge-deploy-safety-hardening.md)

## Context

Supervisors, the desktop instance, and the Telegram bot all operate on the **same** working tree (e.g. `/workspace/<repo>`). Concurrent passes collide on the shared branch/index — the documented failure: "a concurrent instance checked out main, FF-merged, and deleted the task branch under this session." Git worktrees (a native Claude Code feature, `claude --worktree`) give each pass its own checkout sharing the same repo/refs.

The wrinkle: the loop's **state** — `TASKS.md`, `PROGRESS.md`, `.claude-runs/` (verify flags), and the `.phalanx-*` markers — must stay **shared** across the primary and all worktrees. A worktree is a fresh checkout without these untracked files, so a naive `--worktree` would make a pass check off a throwaway `TASKS.md` and never drain the backlog (infinite loop), and would let worktree code bypass the gates.

## Decision

The supervisor runs each pass in its own worktree (`claude --worktree`, under `.claude/worktrees/`); state stays shared at the primary root; the merge lands in the primary tree.

1. **State resolves to the shared root.** `repoRoot()` resolves via `git rev-parse --git-common-dir` (the `.git` all worktrees share) → the primary root, identical from any worktree. `readRepoFile()` (TASKS.md/PROGRESS.md), the verify-flag path, and the `.phalanx-*` marker lookups all use it. For a normal (worktree-less) repo this equals `--show-toplevel` — no behavior change.
2. **Worktree code is still gated.** `metaRe`'s `/.claude/` exclusion gains a negative lookahead `(?!worktrees/)`, so config under `.claude/` stays excluded but real project code under `.claude/worktrees/` is gated (standards, seed-before-edit, no-commit-before-verify).
3. **Land in the primary tree (stays on `main`).** A worktree can't `git checkout main` (main is checked out in the primary). The orchestrator lands with `git -C <primary> merge --no-ff <branch>` then `git -C <primary> push origin main`. The merge gate (5c/5d) recognizes this: `GIT_MERGE` accepts a leading `-C <path>`, and `intoMain` checks the **`-C` target tree's** branch (not the worktree's), so a land from a worktree is still gated for green + opt-in + migration.
4. **Lifecycle.** The supervisor creates the worktree per pass and `git worktree remove --force`s it after (non-interactive `--worktree` is not auto-cleaned). `.claude/worktrees/` is git-excluded. Opt out with `PHALANX_NO_WORKTREE=1` (or an older `claude` lacking `--worktree`).

## Consequences

- Concurrent passes/instances no longer collide on the primary tree; the primary stays a stable `main` checkout that only receives serialized merges.
- The three orthogonal opt-ins (ADR-0002) compose cleanly with isolation.
- A small per-pass cost (worktree create/remove). The land is serialized through the primary — acceptable, since the merge is brief and the supervisor is single-instance.

## Verification

- `install.sh` self-test 62: `worktree:edit-sees-shared-seed` (a gate in a worktree counts the shared backlog) and `worktree:seed-gate-from-worktree` (5a fires from a worktree when the shared backlog is empty). Unit tests for `GIT_MERGE -C`, `mergeCwdPath`, and the `metaRe` worktree carve-out.
- End-to-end worktree canary on a throwaway repo + bare remote: an isolated pass sees shared state, commits in its worktree, lands via `git -C <main> merge` (gated), drains the shared `TASKS.md`, and the worktree is removed — zero human.
