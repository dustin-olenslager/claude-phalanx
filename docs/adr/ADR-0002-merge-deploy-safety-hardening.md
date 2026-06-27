# ADR-0002 — Merge + deploy safety hardening

- **Status:** Accepted (2026-06-27)
- **Deciders:** Operator, Phalanx maintainer
- **Amends:** [ADR-0001](ADR-0001-autonomous-merge-deploy-on-green.md)

## Context

ADR-0001 shipped autonomous merge+deploy on green (default-OFF, per-repo `.phalanx-automerge`). Enabling it fleet-wide immediately exposed three failure modes (caught with **zero prod damage**):

1. **Watch-cron + fleet auto-merge = instant fleet runaway.** The `*/5` `phalanx-watch` cron auto-launches a supervisor for any *registry* repo with an open backlog. Adding merge authority to those repos meant the watcher began autonomously pushing open backlogs to live `main` — including a giant multi-phase epic. "May merge" and "may auto-run unattended" had been conflated.
2. **Deploy-vs-unapplied-migration.** A merged branch can contain code that depends on a DB migration not yet applied to prod. `.phalanx-deploy` correctly does not run migrations, so an autonomous deploy would ship code expecting absent columns → 500s. ADR-0001's prod-migration rail only stopped *writing* a migration, not *deploying code that depends on a prior unapplied one*.
3. **`GIT_MERGE` false-positive.** The v1.6.6 matcher caught the word "merge" anywhere after `git`, so `git checkout -b task/merge-x` and `git commit -m "...merge..."` falsely tripped the merge gate.

## Decision

Three independent, default-OFF per-repo opt-ins, plus two gate fixes:

1. **`.phalanx-autorun` (new).** The watch cron auto-launches a repo **only** if it carries this marker. Registry membership ≠ unattended auto-run. This decouples "drive me unattended" from "may merge" — enabling merge never again auto-drives a backlog. The three markers are now orthogonal: `.phalanx-autorun` (watcher may drive), `.phalanx-automerge` (may merge on green), `.phalanx-deploy` (may deploy after merge).
2. **Rule 5d — migration block.** `loop-integrity-gate.js` denies a merge into `main` when the merged branch's diff touches a migration path (`drizzle/ migrations/ prisma/migrations/ alembic/ …`). Non-bypassable. The operator applies the migration to prod, signs off, and merges by hand. prod-DB stays operator-gated, mechanically.
3. **`GIT_MERGE` tightened** to the `git merge` *subcommand* (`\bgit\s+merge\b`), so branch names and commit messages containing "merge" no longer trip 5c/5d.
4. **Codemagic convention (doc).** A mobile repo's `.phalanx-deploy` may end by pushing a `v*` git tag, which triggers the Codemagic APK build/email. No engine change — the loop already has tag-push creds; the tag pattern lives in the per-repo deploy script.

## Consequences

- The fleet runaway is structurally impossible: no repo auto-runs unattended without `.phalanx-autorun`, and migration-bearing work never auto-merges.
- Re-enabling is deliberate and layered: pick a repo, decide independently whether it auto-runs, auto-merges, and deploys.
- Existing watcher behavior changes: repos that previously auto-ran now need `.phalanx-autorun`. This is the intended safe default after the incident.

## Verification

- `install.sh` self-test 60 green, incl. `merge:deny-migration`, `merge:branchname-no-falsetrip` (the GIT_MERGE fix), `watch:autorun-gate`; unit tests for the matchers + migration-path detection; `scripts/test-watch.sh` autorun-gate case.
- End-to-end canary on a throwaway repo with a local bare remote: a migration branch is **denied** (5d); a clean branch goes green → merge → deploy → **Codemagic tag pushed**, zero human.
