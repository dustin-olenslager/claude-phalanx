# Plan: One shared plan-doc contract across every harness

- **Area:** `shared-plan-contract` · **Started:** 2026-09-17 · **Status:** Complete
- **Owner:** operator (Dustin) · driven this session by OpenCode
- **Next step:** Shipped. Restart opencode to pick up the new `instructions` field (config loads once at startup). The follow-up repair pass (the three drift classes below) is the next initiative.
- **Roadmap initiative:** Harness parity — same plan docs, same work, whichever agent drives.

## Goal

After this ships, whether the operator works through Claude Code or OpenCode, **the same plan
document is read and the same plan document is written** — every time, in every repo under
`/workspace`. The mechanism is that the contract stops being prose one harness reads and instead
becomes (a) a file both harnesses are explicitly pointed at, and (b) a drift check that names every
repo that violates it, so a repo cannot quietly fall out of the convention.

**Success:** `opencode debug config` shows the contract in `instructions`; a single script reports,
per repo, whether the plan docs exist, are git-tracked, and carry the expected files; the report is
the thing the operator acts on.

**Out of scope this pass:** writing to the 14 project repos. The 6 repos whose `docs/claude/` is
untracked, and the 3 repos with a broken `AGENTS.md`/`CLAUDE.md` pair, are **reported, not
repaired** — several have active worktrees and mid-task dirty state. Repairs are a follow-up plan.

## Context

The contract already exists; application is what drifted. Evidence gathered 2026-09-17:

- **Canonical contract:** `/workspace/PANOPLY-OPTIMIZATION.md` (§1 the one rule; §2 project→repo map;
  §1a one backlog in `docs/claude/in-progress.d/<slug>.md`). The Panoply kit states it; Phalanx
  enforces it (ADR-0006, `~/.claude/phalanx-docs-reconcile.sh`, `phalanx-gc.sh`).
- **Opencode side:** `/config/.config/opencode/AGENTS.md` is a 27-line workspace stub that points at
  the contract. `opencode.jsonc` has **no `instructions` field** — opencode relies on the default
  `AGENTS.md` convention, so the contract loads only as a stub, not as the real doc.
- **Claude side:** `/config/.claude/CLAUDE.md` is the full ~21KB §0–§17 operating manual, plus
  `@core.md` + `@fleet.md`. It does **not** reference `PANOPLY-OPTIMIZATION.md` at all.
- **Per-repo drift measured:**

  | Repo | `docs/claude/` tracked | `AGENTS.md` | Notes |
  |---|---|---|---|
  | claude-code-factory | **no** | MIRROR ok | docs on disk, never committed |
  | claude-phalanx | **no** | MIRROR ok | docs on disk, never committed |
  | depona | yes | MIRROR ok | |
  | flutter | **no** | MIRROR ok | branch `stable` |
  | fonto | yes | MIRROR ok | |
  | frame-forge | yes | MIRROR ok | 78 fragments |
  | fylo | yes | **none** | no `AGENTS.md`; `CLAUDE.md` does not import one |
  | hive-edge-fallback | **no** | MIRROR ok | mid-work dirty |
  | levio | yes | **stub** | 116-byte `AGENTS.md` |
  | nexalog | yes | **bespoke** | no `CLAUDE.md`, no `.claude/rules/` |
  | ordica | **no** | MIRROR ok | mid-work dirty |
  | platform | **no** | MIRROR ok | |
  | plexo | yes | MIRROR ok | no `scripts/check-docs.sh` |
  | pushd | yes | **no MIRROR** | `sync-agents.sh --check` FAILS |

- **Constraint that rules out the obvious fix:** opencode config is loaded once at startup and is not
  hot-reloaded, so the operator must restart opencode after the `instructions` change. Also,
  opencode's `instructions` entries are paths/globs relative to the config or absolute — it does not
  expand Claude's `@file` import syntax, so the contract must be listed as its own path.
- **Ownership of this plan:** the change spans repos, which §7 says to route through the operator —
  done; home chosen as `claude-phalanx`, the repo that enforces the contract.

## Architecture

Not application code — this changes the harness configuration plane and adds a read-only reporting
script. The Clean Architecture rows are "none" except the adapter note.

- **Layers touched:** none of Entities/Domain · Use Cases · Interface Adapters · Frameworks (this is
  config data + a shell reporter, outside any app's architecture boundary).
- **New ports (interfaces):** none.
- **Boundary data:** none.
- **Dependency direction:** n/a.
- **Swap test:** the vendor is the agent harness. The harness-specific bindings stay in each
  harness's own config file (opencode's `opencode.jsonc`, Claude's `CLAUDE.md`); the shared contract
  (`PANOPLY-OPTIMIZATION.md`) stays harness-neutral. If a change made the contract itself
  harness-specific, the split would be wrong.

## Milestones

- [x] **M1 — point opencode at the contract** — added
  `"instructions": ["/workspace/PANOPLY-OPTIMIZATION.md", "AGENTS.md"]` to
  `/config/.config/opencode/opencode.jsonc`. Validated: `opencode debug config` shows both entries.
  Backup saved: `opencode.jsonc.bak-sharedplan-20260917-234939`.
- [x] **M2 — point Claude at the same contract** — added a "Plan-home contract (shared with
  OpenCode)" section to `/config/.claude/core.md` (the harness-neutral layer, not the managed block
  that `install.sh` overwrites). Names `/workspace/PANOPLY-OPTIMIZATION.md` as canonical and notes
  not to fork the wording.
- [x] **M3 — the drift check** — wrote `claude-phalanx/scripts/plan-contract-drift.sh`: read-only,
  one line per repo, exit 1 on any missing/untracked artifact. Checks roadmap, queue, worklog,
  AGENTS.md, and the MIRROR block.
- [x] **M4 — run it, record the baseline** — run across all 14 repos; baseline below.
- [x] **M5 — docs** — this file; roadmap → Shipped; worklog + completed-features; in-progress row
  removed. Opencode restart required.

## Drift baseline (2026-09-17)

```
REPO                   ROADMAP   QUEUE    WORKLOG   AGENTS    MIRROR
claude-code-factory    UNTRACKED ok       UNTRACKED ok        ok
claude-phalanx         UNTRACKED ok       UNTRACKED ok        ok
depona                 ok        ok       ok        ok        ok
flutter                UNTRACKED ok       ok        ok        ok
fonto                  ok        ok       ok        ok        ok
frame-forge            ok        ok       ok        ok        ok
fylo                   ok        ok       ok        MISSING   no-mirror
hive-edge-fallback     UNTRACKED ok       UNTRACKED ok        ok
levio                  ok        ok       MISSING   ok        no-mirror
nexalog                ok        MISSING  MISSING   ok        no-mirror
ordica                 UNTRACKED ok       UNTRACKED ok        ok
platform               UNTRACKED ok       UNTRACKED ok        ok
plexo                  ok        ok       ok        ok        ok
pushd                  ok        ok       ok        ok        no-mirror
```

Three drift classes, for the follow-up repair pass:
1. **Untracked docs** (6): claude-code-factory, claude-phalanx, flutter, hive-edge-fallback,
   ordica, platform — `docs/claude/` on disk but never committed.
2. **Missing/stub AGENTS.md** (1 + 2 stubs): fylo (none), levio (116-byte stub), nexalog (bespoke,
   no `.claude/rules/`, no `CLAUDE.md`).
3. **Broken MIRROR** (1): pushd — `sync-agents.sh --check` fails; `AGENTS.md` has no MIRROR block.

## Open questions

- [x] Exact injection point for the Claude-side pointer: resolved to `core.md` (shared,
  harness-neutral; a Phalanx re-install cannot clobber it).
- [ ] Should the drift check live only in `claude-phalanx/scripts/` (versioned) or also be symlinked
  to `~/.claude/` for fleet-wide `phalanx-gc.sh` integration? — _not blocking; candidate follow-up._

## Build notes

> **Build note:** 2026-09-17 — the plan was initially going to write to the 6 untracked-doc repos in
> the same pass; operator scoped it to harness config + contract only. The 6-repo repair is now a
> separate follow-up, which is why M4 records a baseline instead of fixing.

## On ship

Move this folder to `shared-plan-contract/completed/`, add the `completed-features.md` entry, append
the worklog line, remove the `in-progress.md` row, move the roadmap initiative to Shipped, and
promote the "opencode needs a restart after `instructions` changes" gotcha to `key-patterns.md`.
