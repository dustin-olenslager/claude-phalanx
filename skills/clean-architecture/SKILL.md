---
name: clean-architecture
description: >
  ALWAYS-ON architecture standard. Every time code is PLANNED or WRITTEN (any
  language, you or a subagent) you MUST apply Clean Architecture: dependencies
  point inward only, business rules never import frameworks/IO, and every
  external concern sits behind a port (interface) implemented by an adapter at
  the edge. Use whenever planning a feature, designing modules/services/layers,
  starting a new app, adding a use case, deciding where a file goes, wiring a
  database/HTTP/queue, or whenever the user says "architecture", "layers", "use
  case", "port", "adapter", "domain", "where should this live", or "how should
  this be structured".
license: MIT
---

# Clean Architecture — the structural standard

Always-on at **plan time** (decide boundaries) and **write time** (place code,
point deps inward). Enforced at edit-time by `effect-ca-gate.js` and
**mechanically at verify** by `arch-enforce` (dependency-cruiser / import-linter
/ ArchUnit). Off: "stop clean-arch" → `touch <CLAUDE_DIR>/.ts-arch-off`.

## The one rule (ELI5)
Circles inside circles. Inside = business rules; outside = db, web, UI, clock —
replaceable details. **Source dependencies point INWARD only.** Inside knows
nothing about outside → swap Postgres for SQLite, REST for gRPC, without
touching a rule.

## Four layers (inner → outer)
1. **Entities/Domain** — pure types, invariants, value objects, domain errors.
   Zero framework/IO/other-layer imports.
2. **Use Cases/Application** — orchestrate entities for one user intent; depend
   on **ports** they declare, never concrete IO. (TS: an `Effect` over port tags.)
3. **Interface Adapters** — controllers, presenters, gateways, repositories;
   implement the ports; translate to/from the outside.
4. **Frameworks & Drivers** — db, web server, ORM, SDKs, fs, env, main(). The
   replaceable edge; the composition root lives here.

**Dependency Rule:** layer N references inward only. Inner naming outer = the #1
violation — invert it.

## Dependency Inversion
Use case *owns* the interface; adapter *implements* it. Data crosses boundaries
as a domain type/DTO the inner layer defines — never a framework object (no ORM
entity, no `Request`, no raw row leaking inward). TS: port = `Context.Tag`/
`Effect.Service`; adapter = a `Layer`; one composition root provides + runs.

## The pass — plan time AND per file
1. **Which layer is this?** Name it. Can't → responsibility unclear, split.
2. **Which way do imports point?** Inward only; else introduce a port.
3. **Business rule touching IO/framework directly?** Move IO behind a port. No
   `fetch`/`db`/`fs`/`Date.now()`/`Math.random()` in domain or use-case code.
4. **Framework type crossing a boundary?** Map to a domain/DTO; validate input
   there (TS: `Schema.decodeUnknown`).
5. **Wiring?** One composition root at the edge; everything else receives deps.
6. **YAGNI (ponytail):** small app → fewer, fatter layers is fine. Keep the
   *direction* of deps even when collapsing the *number* of layers.

## Suggested layout (adapt)
```
src/domain/        # entities, value objects, domain errors  (no imports out)
src/application/   # use cases + PORT interfaces they declare
src/adapters/      # repositories, controllers, gateways (implement ports)
src/infra/         # db client, http server, SDKs, config
src/main.ts        # composition root: build layers, run once
```

## Hard rules
1. Deps inward only; inner imports nothing from outer.
2. Domain + use cases contain no framework/IO imports.
3. Every external concern (db, http, queue, fs, clock, random, env) behind a
   port owned by the inner layer.
4. Boundaries cross with domain types/DTOs, never framework objects/rows.
5. One composition root wires concrete adapters to ports.
6. Test use cases against fake adapters — no real IO.
7. Encode 1–4 as machine rules in the arch-enforce config; verify fails on
   violation (not vibes).

## Record
New boundary/dependency/layer decision → reason via `system-design`, record via
`adr`. Don't re-decide what an existing ADR settled.
