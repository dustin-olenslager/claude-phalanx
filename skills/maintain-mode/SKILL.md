---
name: maintain-mode
description: >
  MAINTAIN mode driver (CLAUDE.md §15) — changing EXISTING code safely.
  Comprehend before you touch, pin behavior with characterization tests, make the
  smallest safe diff that respects existing patterns. Use when working in an
  established repo, fixing a bug, or when the user says "maintain", "change
  existing code", "fix this bug", "modify the existing".
license: MIT
---

# maintain-mode

You did not write this code. Respect it. Comprehend → characterize → smallest
safe diff. This skill also sets the pipeline `planned` flag.

## Phases (state machine)
1. **comprehend** (exit: model built) — map the relevant slice with a read-only,
   output-capped subagent: entry points, the change seam, data flow, existing
   layer/error/test conventions, the composition root. Do NOT impose new layers
   or your preferred idioms on a codebase that chose otherwise.
2. **characterize** (exit: seam pinned) — BEFORE editing, write characterization
   tests that lock current observable behavior around the seam (even "wrong"
   behavior — you're pinning, not fixing yet). Now a regression is visible.
3. **plan-change** (exit: plan exists) — phased-plan for the SMALLEST diff that
   solves it. Match surrounding style, naming, error handling. New deps/layers
   need a one-line justification (ponytail) — usually the answer is "no".
4. **implement / review / security / verify / commit / memory** — as BUILD, but
   review must confirm the characterization tests still pass (no silent behavior
   change) plus the intended new test goes green.

## Rules
- Smallest reversible change that works. No drive-by refactors in a bugfix diff
  (flag them separately, e.g. a follow-up task).
- Clean Architecture still applies to NEW code you add — but you inherit the
  existing structure; don't rewrite the world to satisfy it. If the seam badly
  violates CA and the fix needs it, raise an ADR, don't sneak a rewrite.
- Keep the change behind the same boundary it lives in; don't widen public API
  without cause.

## Output
Comprehension model (≤300 words) · seam + characterization tests · the minimal
plan · then execute phase by phase.
