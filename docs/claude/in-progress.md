# In Progress

**Read this first.** The ordered queue of what is next. Top of the list is what to pick up now.
Every item points at a plan doc — if an item has no plan doc, it is not ready to start.

The **Notes** cell of the active row is its handoff: keep the *exact next step* there — the file to
open, the command to run, the blocker — refreshed whenever you pause, so the next session resumes
cold. A row with no next step is a row nobody can pick up. (Doctrine: `.claude/rules/documentation.md`.)

Each row rolls up to a `roadmap.md` initiative (the strategic view) and leaves a trail in the worklog
(`worklog.md` or the `CHANGELOG` `[Unreleased]`). A row with no initiative is tactical work with no
strategic home — add the initiative to `roadmap.md`, or say in Notes why it is a deliberate one-off.

When an item ships: remove its row from here, move its folder into `<area>/completed/`, and add an
entry to `completed-features.md`.

## Active queue

| # | Item | Area | Initiative | Plan doc | Status | Notes |
|---|------|------|------------|----------|--------|-------|
| 1 | Reconcile the vendored Panoply kit against upstream (`/workspace/panoply` @ `c1216b7`, v1.3.0 + `[Unreleased]`) | repo | Harness parity — kit currency | none yet — decide scope first, then write `shared-plan-contract/kit-refresh/plan.md` | Not started — **needs an operator scope decision** | **Verified by diff, 2026-09-21.** Current: `scripts/check-docs.sh`, `scripts/init-repo-protection.sh`. **Behind upstream:** `scripts/check-expert-review.sh` (upstream prints `$reason`; guards `grep \| wc -l` with a documented `SC2126` disable; makes persona sign-offs **opt-in** via `EXPERT_REVIEW_REQUIRE_SIGNOFFS=1` instead of arming whenever `gh` is authenticated — the old behaviour would have silently started requiring sign-offs in every repo the moment a `GH_TOKEN` appeared in a workflow; and accepts any `- [ ]`/`- [x]` item under `docs/claude/**` instead of demanding a separate `checklist.md` with an *unchecked* item, which blocked *finished* work) and `scripts/sync-agents.sh` (upstream names Codex/OpenCode as AGENTS.md-native, so they no longer get a redundant mirror). **Mixed adaptation + staleness:** `scripts/templates/ci-verify.yml`, `scripts/templates/pre-commit` (per-repo command fills are legitimate; upstream's newer `HONEST NOTE`, `<ARCH_CHECK_CMD>` and `check-plan-home.sh` plan-home step are not present here). **Missing entirely:** `scripts/check-plan-home.sh`. Also stale in prose: `.claude/rules/workflow.md` → "Expert Review" still lists the old 4-item evidence contract (unchecked `checklist.md` + new ADR + auto sign-offs) that upstream's script no longer implements — editing that module means re-running `sh scripts/sync-agents.sh` (~20 mirrors). **Next step:** ask the operator whether to re-adapt fleet-wide (13 repos) or per-repo on touch, and which template lines are adaptations; do not hand-merge templates without that answer. |
| 2 | | | | | Not started | |
| 3 | | | | | Not started | |

**Status vocabulary:** `Not started` · `In progress — milestone N of M` · `Blocked — <on what>` ·
`In review` · `Done — archiving`.

## Blocked / waiting

Items that cannot move, and the one thing each is waiting on. Review this list before starting
anything new — an unblocked item here outranks a fresh one.

| Item | Blocked on | Since |
|------|-----------|-------|
| | | |

## Parked

Ideas deliberately deferred. Keep the reason — "we said no because X" is what stops the same
proposal coming back every month.

| Item | Why parked | Revisit when |
|------|-----------|--------------|
| | | |
