---
name: gc-loop
description: >
  OPT-IN cleanup / GC loop (Item 4) — a recurring, SOFT maintenance scan that hunts
  drift (TODO/FIXME/HACK/XXX) and stale docs (broken relative links), writes a cheap
  quality grade, and optionally opens a fix-up PR for human review. It is NEVER a gate
  and NEVER blocks a merge. Use when the user says "gc", "cleanup loop", "scan for
  drift", "stale docs", "quality grade", or wants recurring repo hygiene.
license: MIT
---

# gc-loop

Recurring janitor for an established repo. Surfaces rot as a reviewable PR; it does
not fail builds and does not gate merges (deliberately soft — see CLAUDE.md §17:
the GC loop is a maintenance convenience, not a wall).

## Opt-in (default OFF — nothing runs until you turn it on)
Two keys, mirroring the rest of Phalanx:
1. `touch <CLAUDE_DIR>/.gc-on` — the machine-local switch.
2. set `gc.enabled: true` in `<CLAUDE_DIR>/risk-policy.json` — the versioned master.

With neither, `scripts/gc-scan.sh` is a NO-OP: it prints why and exits 0, writing and
changing nothing. This is what keeps existing installs byte-identical after a release.

## What it does (when on)
- **drift** — counts TODO/FIXME/HACK/XXX markers across the tree.
- **stale docs** — flags relative markdown links whose target file no longer exists.
- **grade** — writes `gc.gradesFile` (default `quality-grades.json`): `{ grade, driftMarkers,
  brokenDocLinks, scannedAt }`. Grade is a cheap heuristic — tune the thresholds in policy.
- **fix-up PR (second opt-in)** — only with `--open-pr` (or `PHALANX_GC_OPEN_PR=1`) AND an
  authed `gh`: commits the refreshed grade on a `chore/gc-<stamp>` branch and opens a PR.
  Push/PR is a separate, explicit opt-in so the scan never touches a remote on its own.

## Run it
```sh
scripts/gc-scan.sh -r <repo>              # scan + grade only
scripts/gc-scan.sh -r <repo> --open-pr    # also open a fix-up PR (needs gh)
```
Recurring: drive it from cron or the supervisor's idle cycle. It is independent of the
build/maintain/optimize phase machine — a standalone hygiene pass, not an inline phase.

## Boundaries
Soft by construction. It never edits source automatically, never blocks a gate or a
merge, and degrades to a no-op when off or when `gh`/`git` are absent.
