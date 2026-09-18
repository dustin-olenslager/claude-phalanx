# docs/claude — project knowledge base

Committed, team-shared context for both humans and Claude Code. Everything here is written to be
read under context pressure: short, dated, and specific. Personal preferences and machine-local
setup do **not** belong here — those live in your own `~/.claude/` memory.

## Read order

Start at the top; read what bears on the task, not everything every time.

1. `roadmap.md` — the overall plan: initiatives in Now/Next/Later. Read with `in-progress.md`.
2. `in-progress.md` — the ordered queue of what is next, with plan-doc pointers. **Always read first among the tactical docs.**
3. `architecture.md` — decisions and their reasoning (ADR entries).
4. `key-patterns.md` — conventions, gotchas, testing practice.
5. `infrastructure.md` — deploy, hosting, data stores, secrets, background jobs.
6. `completed-features.md` — what already exists, so you do not rebuild it.
7. `worklog.md` — the running per-change history (or the repo's `CHANGELOG` `[Unreleased]`); skim for what landed recently.
8. The relevant **area folder** — active plans and research for the thing you are changing.

## Layout

```
docs/claude/
  README.md               this file
  roadmap.md              canonical overall plan (initiatives, Now/Next/Later)
  in-progress.md          ordered queue of active work, rolls up into roadmap.md
  worklog.md              running per-change log (omit if the repo uses CHANGELOG [Unreleased])
  completed-features.md   shipped log, with archive paths
  architecture.md         decisions worth recording (ADRs)
  infrastructure.md       how it runs and deploys
  key-patterns.md         patterns, gotchas, testing conventions
  _templates/
    plan.md               copy this to start any plan
    feature-area/         the per-area folder convention
  reports/                dated command-output reports (e.g. stack-assessment-<date>.md)
  <area>/                 e.g. api/, ui/, data/, integrations/
    <feature>/plan.md     active work
    completed/            archived, renamed on ship
```

Never create flat files at the top of `docs/claude/` — new work goes in an area folder.

`reports/` is the one exception to the lifecycle below: it is an **append-only dated archive** of
command-generated reports (`/assess-stack --save` and similar). Reports are history — they are
never moved to `completed/`, never pruned as stale, and old reports naming since-removed things
are the point, not a defect. Newest file wins; earlier ones exist for trend comparison.

## Lifecycle of a doc

1. **Plan** — copy `_templates/plan.md` into `<area>/<feature>/plan.md`; link it from `in-progress.md`.
2. **Build** — re-read the plan at the start of each milestone; tick milestones off; record surprises
   inline with `> **Build note:**` at the moment you find them; append a `worklog.md` line (or a
   `CHANGELOG` `[Unreleased]` line) in the same commit as each landed change.
3. **Ship** — move the whole `<feature>/` folder into `<area>/completed/`, rename files to describe
   what shipped, add a row to `completed-features.md`, remove the item from `in-progress.md`, and move
   the initiative in `roadmap.md` (to Shipped if it was its last plan).
4. **Promote** — anything durable the build taught you (a decision, a gotcha) graduates out of the
   plan into `architecture.md` or `key-patterns.md`. Plans are archived; those two files are living.

Archive, never delete. Update docs in the same PR as the code they describe.
