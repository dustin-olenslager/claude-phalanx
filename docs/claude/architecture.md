# Architecture

Decisions and their reasoning. Not a description of the code — the code describes itself. Record a
decision here when a future reader would otherwise ask "why is it like this?" and be tempted to
change it back.

## System shape

_One paragraph plus a rough diagram or component list: the major pieces and how a request flows
through them end to end._

## Boundaries and ownership

- What owns the data, and what may only read it?
- Where is the source of truth for shared types, enums, and constants?
- Which modules are allowed to depend on which? Name the dependency direction that must not reverse.

## Data model

- Which entities are core, and what identifies them?
- **Normalized rows vs. blob columns:** anything that will be queried, filtered, aggregated, or
  reported on gets its own rows and columns. Blob/JSON columns are for opaque payloads only —
  they are not queryable, joinable, or indexable, and rewriting them later is a migration.
- What is intentionally denormalized, and what keeps the copies in sync?

## Cross-cutting decisions

- Authentication and authorization model.
- Error shape returned across boundaries, and how failures surface to the user.
- Versioning and backward-compatibility policy for public interfaces.
- What is deliberately **not** in scope for this system.

---

## ADR template

Copy this block for each decision. Number sequentially; never renumber or delete a superseded ADR —
mark it `Superseded by ADR-NNNN` so the reasoning trail survives.

```markdown
### ADR-0001 — <short decision title>
- **Date:** YYYY-MM-DD
- **Status:** Accepted | Superseded by ADR-NNNN | Reversed
- **Context:** the forces in play — constraints, scale, deadlines, what we knew at the time.
- **Options considered:** each one, with its honest tradeoffs. Include the option we rejected.
- **Decision:** what we chose.
- **Consequences:** what this makes easy, what it makes hard, and what would force a revisit.
```
