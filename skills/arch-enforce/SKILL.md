---
name: arch-enforce
description: >
  Verify-phase gate that enforces Clean Architecture MECHANICALLY (not by vibes)
  with a dependency linter: dependency-cruiser (JS/TS), import-linter (Python),
  ArchUnit (JVM), or the language's equivalent. Use in the verify phase, when
  setting up a new repo's guardrails, or when the user says "enforce architecture",
  "dependency rules", "layering check", "dependency-cruiser".
license: MIT
---

# arch-enforce

Turn the Clean Architecture rules (§3/§14) into machine-checked rules that fail
CI. Vibes don't catch a sneaky `import` at 2am; a linter does.

## Per-language tool
- **TS/JS** → `dependency-cruiser` (`depcruise --config .dependency-cruiser.js src`).
- **Python** → `import-linter` (layers/forbidden contracts in `.importlinter`).
- **Kotlin/JVM** → `ArchUnit` (a test class asserting layer access).
- **Rust** → crate boundaries + `cargo-deny`/clippy; **Go** → `go-arch-lint` or
  internal/ package boundaries + `golangci-lint`.

## The rules to encode (every project)
1. `domain` may import nothing from `application`, `adapters`, or `infra`.
2. `application` may import `domain` only — never `adapters`/`infra`/frameworks.
3. `adapters` may import `domain` + `application` (ports) — never sibling
   adapters' internals.
4. Only the composition root (`main`/`infra/bootstrap`) may import concrete
   adapters/infra and wire them.
5. No `infra`/framework symbol reachable from `domain`/`application` (no `fetch`,
   db client, ORM, `fs`, http types inward).
6. No orphan/dead modules; no circular dependencies.

## Process
1. If no config exists, generate one from the repo's actual layer dirs (a starter
   `.dependency-cruiser.js` ships in `configs/`). Map rule-set above to its
   `forbidden` array; `severity: "error"`.
2. Run it. Report violations as `from → to (rule)`; each is blocking.
3. Wire it into the verify gate + CI so a layering breach fails the build. The
   pipeline-gate counts `dependency-cruiser`/`depcruise`/`import-linter`/`archunit`
   as a verify action.
4. Fix by dependency inversion (introduce a port), never by relaxing the rule.

## Output
```
arch-enforce: <tool> — <N> violations
<from> → <to>  (<rule>)   [each]
verdict: PASS | FAIL (FAIL blocks verify)
```
