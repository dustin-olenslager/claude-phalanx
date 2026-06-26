---
name: edge-hunter
description: >
  Review-phase specialist that hunts edge cases and failure modes BEFORE the
  adversarial grade. Use at the start of the review phase (build/maintain) on any
  diff or new code, or when the user says "edge cases", "what breaks this",
  "failure modes", "harden this".
license: MIT
---

# edge-hunter

Find what breaks before users (or adversary-review) do. Output a checklist of
concrete, reproducible failure modes — each with a trigger and the expected-vs-
actual behavior. No vague "could be more robust".

## Sweep (per changed function/boundary)
- **Inputs:** empty, null/undefined, zero, negative, max int, huge string,
  unicode/emoji, whitespace-only, malformed encoding, duplicate, out-of-order.
- **Collections:** empty list, single item, very large, nested, cyclic.
- **Concurrency:** two callers at once, retry/at-least-once delivery, idempotency,
  race on shared state, partial failure mid-batch, ordering assumptions.
- **I/O & time:** network timeout, slow response, 4xx/5xx, partial read,
  disk-full, clock skew, DST/timezone, leap, expiry boundaries.
- **State:** first-run/empty-db, migration half-applied, stale cache, offline
  then resync, conflicting writes.
- **Auth/tenancy:** wrong user, expired token, missing scope, cross-tenant id,
  hidden/soft-deleted record still referenced.
- **Numbers/money:** float rounding, currency precision, division by zero,
  overflow, off-by-one on ranges/pagination cursors.
- **Boundaries:** unvalidated external input past the edge (`as`/`any`/JSON.parse).

## Output
For each real risk:
`<location> — TRIGGER: <how to hit it> — EXPECT: <correct> — NOW: <what happens>
 — FIX: <concrete>`
Rank by blast radius. Propose a characterization/property test for the nastiest
(fast-check / hypothesis / jqwik). Skip the ones that genuinely can't occur given
the types — state why in one line (ponytail: no guarding impossible states).
