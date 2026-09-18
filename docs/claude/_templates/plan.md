# Plan: <feature name>

- **Area:** `<area>`  ·  **Started:** YYYY-MM-DD  ·  **Status:** In progress
- **Owner:** <who is driving this>
- **Next step:** the exact next action to resume this cold — the file to open, the function to change, the command to run, the blocker. Refresh it every time you stop. _(This is the handoff: a plan with a stale or empty Next step cannot be picked up cold — see `.claude/rules/documentation.md`.)_
- **Roadmap initiative:** the `../../roadmap.md` initiative this plan executes _(delete if this is a standalone one-off with no strategic home — but prefer to name one)_.
- **Parent plan:** _(link if this is a sub-milestone; otherwise delete)_

## Goal

One paragraph. What is true after this ships that is not true now, stated in terms of what a user or
caller can do. Include how we will know it worked.

**Out of scope:** what this deliberately does not do. Naming this prevents scope creep mid-build.

## Context

What a fresh session needs to know to pick this up cold: the current behavior, the files and modules
involved, relevant decisions already made (link the ADR in `../../architecture.md`), and any
constraint that rules out the obvious approach.

## Architecture

Fill this before the first milestone — a plan that cannot name its layers is not ready to build (see
`.claude/rules/clean-architecture.md`). Write "none" where a row genuinely does not apply; delete no row.

- **Layers touched:** which of Entities/Domain · Use Cases/Application · Interface Adapters ·
  Frameworks & Drivers this change adds to or modifies.
- **New ports (interfaces):** name each, the use-case layer it is declared in, and the adapter that
  implements it — or "none".
- **Boundary data:** the DTOs crossing each boundary. Confirm no domain entity is serialized to the
  wire or handed to an ORM by reflection.
- **Dependency direction:** confirm every new dependency points inward. If any points outward, stop —
  raise it in Open questions and get a decision before building (`quality-bar.md`).
- **Swap test:** name the vendor/framework this touches; the diff to replace it must stay inside
  Interface Adapters + Frameworks & Drivers. If an entity or use-case file would appear in that diff,
  the design is not done.

## Milestones

Each milestone is independently reviewable and leaves the system working. Re-read this section at
the start of each one.

- [ ] **M1 — <name>** — <what changes, which files>
- [ ] **M2 — <name>** — <what changes, which files>
- [ ] **M3 — <name>** — tests, docs, and cleanup of anything the change orphaned

If a milestone splits into sub-milestones, nest them below their parent or create a sibling file in
this folder and link it here. **Do not overwrite this file** — the parent plan must stay readable as
a high-level overview.

## Open questions

Blocking decisions for the user, not for you to resolve unilaterally. Delete each one once answered,
recording the answer in Context.

- [ ] <question> — _blocks M2_

## Build notes

Record deviations and discoveries **at the moment you find them**, inline next to the milestone they
affect or appended here. Written later, they are written wrong.

> **Build note:** YYYY-MM-DD — what we expected, what was actually true, and what changed as a result.

## On ship

Move this whole folder into `<area>/completed/`, rename this file to describe what shipped, add an
entry to `../../completed-features.md`, append the final line to the worklog (`../../worklog.md` or the
repo's `CHANGELOG` `[Unreleased]`), remove the item from `../../in-progress.md`, MOVE the initiative in
`../../roadmap.md` (to Shipped if this was its last plan), and promote any durable lesson into
`architecture.md` or `key-patterns.md` — all in the same commit as the ship.
