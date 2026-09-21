# Error Handling

> **Applies when:** always — any project that accepts input, performs I/O, or shows results to a user.
> **Delete this file (and its `@` import in `CLAUDE.md`) if:** never. Trim individual rules instead.

## Validate at the boundaries

- Validate every input at the point it enters the system: request params, body, query strings, headers, message payloads, CLI arguments, file contents, environment variables. Inside the boundary, code is entitled to assume the data is well-formed — that assumption is only safe if the boundary actually enforced it.
- Validate with the project's schema/validator, not with hand-rolled `if` chains. A schema is a single declaration that produces both the runtime check and the type, so the two cannot drift apart.
- Reject unknown or extra fields rather than ignoring them. Silently dropping a misspelled field turns a caller's bug into your bug report.
- Validate and normalize before writing to storage. A bad row outlives the request that created it.

## Wrap the things that can actually fail

- Put `try`/`catch` (or the language's equivalent) around **I/O and external calls**: database queries, HTTP requests to other services, file system access, queue publishes, third-party SDK calls. These fail for reasons your code cannot prevent, so they are the places a handler earns its keep.
- Set an explicit timeout on every outbound network call. Without one, a hung dependency becomes a hung request, then an exhausted pool, then an outage.
- Catch narrowly and rethrow what you cannot handle. A catch block that swallows everything hides bugs that have nothing to do with the failure you were guarding against.
- Never leave an empty catch block. If a failure is genuinely ignorable, log it at debug level and write the one-line reason it is ignorable.

## DON'T over-engineer internal error handling

This counter-rule matters as much as the rules above. Defensive code between your own modules is not free — it adds branches nobody tests, hides real failures behind fallbacks, and trains readers to distrust the type system.

- Trust framework and language guarantees between internal modules. Do not null-check a value the type system already proves is non-null. Do not re-validate *shape and format* that the boundary validator already validated. Do not wrap a pure function in `try`/`catch` because it "might" throw.
- The carve-out that is **not** re-validation: entities and use cases enforcing their own *invariants and business rules* (see the validation split in `clean-architecture.md`). The boundary check protects one entrypoint; the domain check protects every entrypoint — jobs, CLIs, tests, other services — and neither substitutes for the other.
- Do not add fallback values that mask a broken invariant. If an internal call returning nothing means the system is in an impossible state, let it throw — a loud crash with a stack trace is more debuggable than a silent default that propagates wrong data for a week.
- Rule of thumb: handle errors where you can **do** something about them (retry, fall back to a real alternative, surface a message to the user). Everywhere else, let them propagate to the boundary handler.

## Errors belong to the layer that raised them

- **A domain or use-case failure is a domain type, not a framework exception.** A broken business rule raises or returns a named domain error (`InsufficientFunds`, `AlreadyClaimed`) — never the web framework's exception class, never a bare status code. Domain code that knows what `409` means cannot be reused by a job, a CLI, or a second transport without dragging the web framework along.
- **Translation from domain error to transport status code happens in the Interface Adapters layer, and nowhere else.** One mapping in one place, so changing the API's error contract is one edit. A status code chosen deep inside a use case is invisible to that mapping and will drift from it — and nothing will fail until a client notices.
- **A use case must never return or raise an HTTP-shaped thing**: no status codes, no response envelopes, no framework error classes. If you cannot write the failure without naming a transport, the rule is in the wrong layer. See `clean-architecture.md`.

## Consistent, typed error responses

- Return errors in one shape across the whole API, defined once as a shared type and reused by every handler. Ad-hoc error bodies force every client to special-case them.
- The shape carries at minimum: a stable machine-readable code, a human-readable message, and (for validation failures) the offending fields. Clients branch on the code, never on the message text.
- Map failure classes to correct status codes — bad input, unauthenticated, forbidden, not found, conflict, upstream failure, unexpected. Returning success-with-an-error-body defeats every client retry and monitoring rule.
- Never leak stack traces, SQL, internal paths, or upstream provider payloads to the caller. Log those; return the code.

## Log with enough context to debug

- Every logged error includes: what operation was running (route/job/handler name), the identifying inputs (record ids, not full payloads), and the underlying error message and stack. A log line that says only `Error: request failed` costs an hour of bisecting.
- Never log secrets, tokens, passwords, full auth headers, or personal data. Log the id, not the record.
- Log the error where you have the context, once. The same failure logged at four levels of the stack makes the real one harder to find.

## Never fail silently — the strongest rule here

**Every user-facing operation that fails must surface the failure to whoever initiated it, and log it.** In a UI, that means a visible error state; in a headless service, the "user" is the caller, and the failure maps to the typed error response — never a swallowed exception, never success-with-nothing-happened.

- If a background operation fails and its initiator cannot act on it, it still gets logged with full context — but say plainly in your change description that it is intentionally silent, so the choice is reviewed rather than assumed.
