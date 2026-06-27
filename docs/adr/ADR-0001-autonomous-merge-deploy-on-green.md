# ADR-0001 — Autonomous merge + deploy on green

- **Status:** Accepted (2026-06-27)
- **Deciders:** Operator, Phalanx maintainer
- **Supersedes:** the standing `branch-only / no-merge / no-deploy` guardrail (§17, orchestrator, work.md)

## Context

Phalanx's loop drives a task to a green verify, commits on `task/<slug>`, and then
**stops** — it pushes a branch and leaves a PR for a human. The stated goal of the
system is autonomous agents working **to completion**. Stopping at the PR means a
human is still in the critical path for every shipped change; the loop proved it can
code and verify, but not finish.

This change gives the loop **production authority**: after a green verify it may merge
to `main` and run a deploy with no human touch. That is the highest-stakes capability
in the system, so every new power is gated **mechanically** (a PreToolUse hook that
hard-denies), not by prose an agent can rationalize away.

## Decision

After a verify ran **green this pass** on `task/<slug>`, the loop may merge → `main`
and run a per-repo deploy — subject to four gates, all enforced in code.

### 1. Green-verify gate (mechanical, non-bypassable)
Reuse the existing cross-pass verify flag (`phalanx-hook.js` `verifyFlagFreshFor`,
keyed repo+branch under `.claude-runs/verified.<branch>`; written by `pipeline-gate.js`
on a green verify/test/lint/typecheck). `loop-integrity-gate.js` gains **rule 5c**: a
`git merge` whose target is `main` is **DENIED** unless the **merged (source) branch's**
verify flag is fresh. The merge runs *from* `main` (`git checkout main && git merge …`),
so the gate parses the source branch out of the command and checks **its** flag, not
`main`'s. This deny **ignores `PHALANX_WARN`** — unlike rules 5a/5b it does not soften on
the bot/cc instance. **Never merge on red, on any instance.**

### 2. Repos in scope (opt-in per repo, default OFF)
A repo gets auto-merge only if it contains a `.phalanx-automerge` marker file the
operator creates. Absent → rule 5c denies the merge and the loop opens a PR (previous
behavior, unchanged). This makes "which repos" a per-repo operator switch, not a global
flip and not a model judgment — fleet-wide is impossible by accident. The first enabled
repo is a single low-blast-radius repo (operator's choice — recoverable, non-money,
non-media) before any wider rollout.

### 3. Deploy convention (per-repo, optional)
An optional executable `.phalanx-deploy` at the repo root. After a successful merge the
orchestrator runs it and records the exit code. **Absent → merge only, report.** Each
repo's deploy is bespoke (one builds and ships over ssh, another bundles and copies a
container image, another runs `compose up`); Phalanx only execs the operator's script —
no deploy framework. Deploy runs
**inside the agent pass**, right after the merge, so it works for the supervised loop and
interactive Desktop alike.

### 4. Push credentials (dedicated, scoped)
A **dedicated** GitHub PAT (classic, `repo` scope — operator's choice), not the broad
account token. Stored cc-readable at `$CLAUDE_DIR/.loop-git-env` (mode 0600) as
`GH_TOKEN=…`. `run-work.sh` injects `GH_TOKEN` **only on the `claude` invocation env**
(same exfil-scoping as the OAuth token — never sourced into the whole pass env, so
curl/ssh/docker children don't inherit a push-capable token). The orchestrator runs
`gh auth setup-git` so `git push` uses it; `gh` uses it directly for PRs. The token is
operator-provisioned config (like `.headless-env`), never committed.

## Rollback

- Merge uses `--no-ff` → one merge commit per task on `main` → clean
  `git revert -m 1 <merge-sha>`.
- Deploy failure does **not** auto-revert `main` (avoids thrash). The orchestrator
  records the merged SHA + deploy exit and writes
  `BLOCKED: deploy failed for <repo> @ <sha>` to PROGRESS.md, halting for the operator,
  who decides revert vs forward-fix. `.phalanx-deploy` owns its own forward-rollback.
- Kill switches: remove `.phalanx-automerge` (disables merge for that repo), `touch
  .work-off`, or "stop loop".

## Safety rails kept (unchanged)

- **Operator-risk HALT:** the RISK regex (data-loss / data-continuity / irreversible /
  drop / truncate / migration cutover / backfill) → `BLOCKED`, **no auto-merge**.
  Enforced in the orchestrator + `work-autostart`; the merge inherits it because a
  risk-flagged task never reaches a green verify without first halting.
- **Prod-DB migrations stay gated:** writing a migration → STOP for sign-off.
- **Verify-before-commit (5b) and seed-before-edit (5a)** are unchanged.

## Consequences

**Positive:** the loop finishes — tested work lands and ships unattended in opted-in
repos. The two prior open risks (push creds gap, "never merge" being prose) are closed
mechanically.

**Negative / accepted:** a green verify that is itself weak could ship a real defect to
`main` of an opted-in repo — mitigated by per-repo opt-in (start with one low-risk repo),
`--no-ff` one-commit revert, and the deploy script owning its own health/rollback. A
classic `repo`-scope PAT is broader than a fine-grained one; mitigated by 0600 cc-only
storage + per-exec env scoping, and flagged for rotation.

## Verification

- `install.sh` self-test green: prior 49 cases + new `merge:deny-not-optedin` (+teach),
  `merge:allow-green-optedin`, `merge:deny-no-green`, `merge:nonbypassable-warn`,
  `merge:branch-local-untouched`, `deploy:script-detected`, `deploy:absent-is-empty`.
- Unit tests for the pure helpers (`mergedBranch`, the matchers) in
  `hooks/gates/lib/tasks-state.test.js`.
- End-to-end proof on a throwaway repo with a local bare remote: seed → branch → green
  verify → commit → merge → deploy → backlog drained, with the **real gates** enforcing
  each decision point and zero human input.
