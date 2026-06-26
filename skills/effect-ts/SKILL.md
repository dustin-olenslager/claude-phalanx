---
name: effect-ts
description: >
  ALWAYS-ON TypeScript implementation standard. Any time you (or a subagent)
  write, refactor, or review TypeScript (.ts/.tsx/.mts/.cts) you MUST consult
  this skill first and default to the Effect (https://effect.website) ecosystem
  for effects, errors, dependency injection, schema/validation, concurrency, and
  observability — instead of raw async/await, throw, try/catch, and hand-rolled
  DI. Use whenever the task involves TypeScript, Node/Deno/Bun services, an API
  layer, a use-case/service module, parsing/validating external input, or
  whenever the user says "TypeScript", "TS", "Effect", "typed errors", "schema",
  "service", or "dependency injection".
license: MIT
---

# Effect-TS — the TypeScript implementation standard

Source of truth: **https://effect.website** (Effect 3.x). Always-on: every TS
edit goes through it. Enforced by `effect-ca-gate.js` + `ts-arch-anchor.sh` +
CLAUDE.md §14. Pairs with **clean-architecture** (Effect is *how* you implement
each CA layer in TS). Off: "stop effect" → `touch <CLAUDE_DIR>/.ts-arch-off`.

## Why (ELI5)
Plain TS hides three things: what can go *wrong*, what a function *needs*, and
whether it's *async*. `Effect<A, E, R>` makes all three explicit — a recipe that
**succeeds with `A`**, **may fail with `E`**, **needs services `R`**, and does
nothing until run. Compiler catches what async/await + throw let slip.

## The pass — before writing TS
1. **Trivial pure glue** (types, constants, one-line mappers, pure fns)? → plain
   TS, no Effect ceremony (YAGNI). Gate wants the skill *consulted*, not every
   line wrapped.
2. **Does it do I/O, can it fail, or need a dependency?** → model as `Effect`.
3. **Pick the CA layer:** domain = pure + Schema; use cases = `Effect`
   depending on port *tags*; adapters = `Layer`s; entrypoint = one run.

## Core idioms (exact names)
**Create:** `Effect.succeed/fail`, `Effect.sync`, `Effect.try({try,catch})`,
`Effect.promise`, `Effect.tryPromise({try,catch})` (replaces raw `await`).

**Compose** — prefer `Effect.gen`:
```ts
import { Effect } from "effect"
const program = Effect.gen(function* () {
  const user = yield* getUser(id)
  return yield* listOrders(user.id)
})
```
Or `pipe(fx, Effect.map(f), Effect.flatMap(g))`. Never `.then`.

**Errors — typed, not thrown:**
```ts
import { Data } from "effect"
class UserNotFound extends Data.TaggedError("UserNotFound")<{ id: string }> {}
```
Handle by tag: `Effect.catchTag`, `Effect.catchTags`. `catchAll`/`catchAllCause`
at boundaries only. `E` channel = expected failures; `Effect.die` = bugs.

**DI — services as `R`.** Prefer `Effect.Service`:
```ts
class Users extends Effect.Service<Users>()("app/Users", {
  effect: Effect.gen(function* () {
    const db = yield* Db
    return { byId: (id: string) => db.query(id) }
  }),
  dependencies: [Db.Default],
}) {}
```
Multi-impl ports → `Context.Tag`. Consume with `yield* Users`.

**Wiring — `Layer`:** `Layer.succeed/effect/scoped`, `Layer.provide`,
`Layer.merge`; provide once: `program.pipe(Effect.provide(AppLayer))`.

**Run — ONE entrypoint:** `Effect.runPromise` / `runFork` (servers) / `runSync`.
Library/use-case code returns Effects, never runs them.

**Boundaries — `effect/Schema`:** `Schema.Struct`, `Schema.decodeUnknown` →
`Effect<A, ParseError>`. Never trust `any`/`as` past the edge.

**Observability (§12):** `Effect.log*`, `Effect.withSpan("name")`,
`Effect.annotateLogs`; export via `@effect/opentelemetry`. Spans on every I/O
boundary + use case from day one.

**Platform/concurrency:** `@effect/platform(-node/-bun)` (HttpClient, FileSystem),
`@effect/sql`; `Effect.all(xs,{concurrency})`, `forEach`, `race`, `timeout`,
`retry(Schedule.*)`, `acquireRelease`/`scoped` for resources.

**Tests:** `@effect/vitest` (`it.effect`), provide **test Layers** for ports,
`fast-check` for properties. Test rules against fakes — no real IO.

## Hard rules
1. No raw async/await for fallible I/O → `Effect.tryPromise`.
2. No `throw` for expected failures → `Data.TaggedError` in `E`.
3. No `new Service()` graphs/singletons → `Effect.Service`/`Layer`.
4. No `JSON.parse`/`as Foo` trust at edges → `Schema.decodeUnknown`.
5. `runPromise`/`runFork`/`runSync` appears once, at the entrypoint.
6. Spans/structured logs on every boundary (§12).

## When NOT to Effectify
Pure helpers, types, plain data, framework config, tiny edits to existing
non-Effect code. State the skip in one line, proceed (ponytail).
