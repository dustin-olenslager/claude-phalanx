---
name: caveman-commit
description: >
  Ultra-compressed commit message generator (Conventional Commits). Subject ≤50
  chars; body only when the "why" isn't obvious. Use when the user says "write a
  commit", "commit message", "generate commit", "/commit", or when staging
  changes. Pipeline phase 13.
license: MIT
---

# caveman-commit

Conventional Commits, caveman-trimmed. Commit BODIES are full English
(caveman-exempt) — the subject is terse, the body is clear.

## Format
```
<type>(<scope>): <subject ≤50 chars, imperative, no trailing period>

<body — only when the change's WHY is non-obvious. Wrap ~72 cols.
 Explain why, not what (the diff shows what).>

<footer — BREAKING CHANGE: …, refs #123, Co-Authored-By: …>
```

## Types
feat · fix · refactor · perf · test · docs · build · ci · chore · revert.

## Rules
- One logical change per commit. Subject completes "If applied, this commit
  will …".
- No body for obvious changes (a typo fix needs no paragraph).
- Body required for: non-obvious why, a tradeoff taken, a gotcha, a revert
  reason, anything an ADR-worthy decision touched.
- Never invent scope; omit if unclear.
- Respect the repo's existing footer conventions (sign-off, co-author, issue
  refs) — read a few recent commits first if unsure.

## Process
1. Read the staged diff (`git diff --cached --stat` then the hunks).
2. Group into the smallest honest set of commits if it's mixed.
3. Emit subject (+ body when warranted). Show it; let the user commit, or commit
   when asked — but only after the verify gate (§13) is satisfied.
