# Roadmap — the overall plan

The one canonical strategic view: the **initiatives** this project is committed to, in priority order.
One row is one initiative — a body of work that spawns several plan docs and several `in-progress.md`
queue rows — **not** a single task.

Three views, three altitudes, no overlap:
- **`roadmap.md` (this file)** — strategic. Initiatives and their band (Now / Next / Later).
- **`in-progress.md`** — tactical. The queue of what is next, which rolls up into these initiatives.
- **The worklog** (`worklog.md`, or the `CHANGELOG` `[Unreleased]` section) — the change history underneath both.

**This file owns exactly three things:** an initiative's *existence*, its *band*, and its *links down*
to the queue rows and plan docs that execute it. It does **not** restate task status — that is derived
from the linked `in-progress.md` rows — so there is almost nothing here to go stale.

**Update it in the SAME change that starts, reprioritises, or finishes an initiative:**
- New initiative → add a row to Now/Next/Later.
- Its first plan doc or queue row → link it here.
- Its last queue row ships → move the row to **Shipped** with the date, in the same commit as the ship.

## Now — in active development

| Initiative | Intent (one line) | Queue rows (`in-progress.md`) | Plan docs |
|---|---|---|---|
| Harness parity — kit currency | Keep the kit vendored into each adapted repo reconciled with panoply upstream, so a stale gate is a decision rather than an accident | row 1 | none yet — scope decision first |

## Next — committed, not yet started

| Initiative | Intent | Depends on |
|---|---|---|
| | | |

## Later — directional, not yet committed

Records the "why we said no / not yet" so the same idea does not get re-proposed every month
(the strategic twin of `in-progress.md` → Parked).

| Initiative | Why it matters | Revisit when |
|---|---|---|
| | | |

## Shipped

Newest first. Each links to the `completed-features.md` entries that make it up — the strategic index
into the feature log.

| Initiative | Shipped | Features (`completed-features.md`) |
|---|---|---|
| Harness parity — opencode | 2026-09-17 | Phalanx config layer ported to opencode (9 subagents + 3 commands) |
| Harness parity — shared plan contract | 2026-09-17 | One plan-doc contract loaded by both harnesses + advisory drift-check |

<!-- Small project? An initiative and a queue row may be nearly the same thing — that is fine. Keep
     this file to a handful of rows; if an initiative needs more than a line, it has become a plan doc,
     not a roadmap entry. But do NOT delete the file: it is step 2 of the AGENTS.md onboarding contract,
     the one place any-provider agent learns the overall arc. -->
