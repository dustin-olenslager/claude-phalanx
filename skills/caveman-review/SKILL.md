---
name: caveman-review
description: >
  Ultra-compressed code-review comments — one line per finding, no prose padding.
  Use when the user says "review this PR", "code review", "review the diff",
  "/review". For the harsh adversarial grade + working fix, pair with
  adversary-review (§16).
license: MIT
---

# caveman-review

One finding = one line. Signal only.

## Line format
`<file>:<line> — <severity> — <problem> → <fix>`

Severity: `BUG` (wrong/will break) · `SEC` (security) · `PERF` · `ARCH`
(layer/dependency violation) · `NIT` (style/clarity).

## Rules
- Quote the offending token/expression, not a paraphrase.
- Every comment carries a concrete fix, not "consider improving".
- Order: BUG → SEC → ARCH → PERF → NIT.
- No "looks good" filler; if a section is clean, say nothing about it.
- Group nothing into prose; bullets/lines only.
- End with a 1-line verdict: `APPROVE` / `APPROVE w/ nits` / `REQUEST CHANGES`.

## Scope checks (always pass over)
- Clean Architecture: any inner→outer import? business rule touching IO? → ARCH.
- Typed errors: a raw `throw`/`await` where the standard wants Effect/Result? → BUG.
- Boundaries: unvalidated external input (`as`, `JSON.parse`, `any`) → SEC/BUG.
- Secrets/PII in code or logs → SEC.
- Dead code, premature abstraction (ponytail) → NIT/ARCH.
