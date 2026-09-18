# Key Patterns & Gotchas

Conventions to follow and traps to avoid, discovered the expensive way. Add to this file the moment
something surprises you — record the **symptom**, not just the fix, because the next person arrives
holding the symptom.

## Conventions

Patterns that new code must match. Keep each one checkable — a reviewer should be able to point at
a line and say "this violates it."

- _Example: use named exports; no default exports — so renames are greppable and re-exports stay explicit._
- _Example: shared enums and constants come from the shared module; no magic strings._
- _Example: all outbound HTTP goes through the single typed client wrapper, not raw fetch calls._

## Gotchas

| Symptom you will see | Actual cause | What to do |
|---|---|---|
| _EXAMPLE — tests pass locally, fail in CI with a timeout_ | _CI runs without the local cache warm_ | _Seed the fixture in `beforeAll`, not lazily_ |
| | | |

## Testing conventions

- What must have a test before it merges — name the categories (business logic, validation,
  transformations, every route/endpoint or public entry point).
- Where tests live and how their paths map to the code under test. State the mapping rule exactly;
  an ambiguous rule means tests get written in three places.
- What gets mocked by default (auth, database, external services) and what must be exercised for real.
- **Never skip, `.only`, or comment out a failing test to get a change through.** Fix it or report it.
- When you change query structure or call ordering, update the mocks in the same change — mocks
  consumed in sequence return the wrong data silently when the order shifts, and the test stays green.

## Performance notes

- Known hot paths and what makes them slow.
- Anything with an N+1 shape that is deliberately tolerated, and the threshold at which it stops
  being acceptable.

## Things that look wrong but are intentional

Guard rails against well-meaning "cleanups" that reintroduce a fixed bug. One line each, with the
reason.
