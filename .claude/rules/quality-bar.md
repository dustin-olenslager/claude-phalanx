# Long-Term Quality Bar

> **Applies when:** always — before proposing any approach, and before any structural decision that is hard to reverse.
> **Delete this file (and its `@` import in `CLAUDE.md`) if:** never. This is the rule that stops the easy path from winning by default.

## The self-check

Before proposing an approach, ask yourself, in writing:

> **"Is this the best choice for a production system that will be used for years, or am I choosing the easier path?"**

Answer it honestly in the proposal. If the answer is "this is easier," say so out loud — the user can accept a shortcut they were told about, and cannot accept one they were not.

Then a second question, cheaper to answer and just as revealing:

> **"Which layer does this belong in, and does anything in it point a dependency outward?"**

If you cannot name the layer, you do not yet understand the change well enough to propose it. If the honest answer is "it points outward," that is a design decision — surface it here rather than letting it arrive as an import. See `clean-architecture.md`.

The path of least resistance is not neutral: it spends someone else's time later to save yours now. Prefer the right structure even when it costs more work up front, and when you don't, name the debt you are taking on.

## Flag tradeoffs explicitly

- When a simpler approach trades away scalability, type safety, maintainability, queryability, testability, or an established best practice, **state the tradeoff and give your honest recommendation.** Not a menu with no opinion — a recommendation, with the reason.
- Quantify where you can: what breaks at 10x the data, what a future change would cost, what the migration out looks like. "It might not scale" is unactionable; "this reads the whole table on every request, so it degrades past roughly N rows" is a decision the user can make.
- If you are proposing the cheaper option deliberately (a prototype, a spike, a deadline), say that it is deliberate and note what would have to change to make it permanent.

## Never dismiss an option without evaluating it

- **"Over-engineered" is a conclusion, not an argument.** Do not use it — or "unnecessary", "premature", "YAGNI" — to skip past an option you have not actually evaluated. Cheap dismissal is how the wrong architecture gets chosen without anyone noticing a choice was made.
- Evaluate every viable option on its own merits: queryability, analytics and reporting, extensibility, type safety, testability, operational cost, and the cost of reversing it later.
- Only after that evaluation may you recommend against an option — and then you must say which merit it loses on.
- This applies with equal force to options the user proposed and options you proposed. Do not defend your first idea; evaluate it the same way.

## Present two options and let the user decide

When the decision is genuinely a judgement call, do not decide silently. Present it like this:

1. **Option A** — one line on what it is; what it costs now; what it costs later.
2. **Option B** — same.
3. **What differs that actually matters** — the one or two axes the choice turns on.
4. **Your recommendation, and why.**

Then stop and wait. Do not start implementing either option while the question is open. Two well-drawn options with honest tradeoffs is a better deliverable than a confident single answer that quietly closed off the alternative.

## Applies to

Run the self-check on any of these before writing code:

- **API design** — endpoint shape, payload contracts, versioning, what the server sends versus what the client must fetch.
- **Data modeling** — table and entity structure, normalized rows versus blob/document columns, junction tables versus polymorphic columns, what gets its own status and timestamps.
- **Type-system choices** — shared types versus duplicated ones, unions versus open strings, where the source of truth for a type lives.
- **Component and module architecture** — boundaries, ownership of state, what is generic versus domain-specific, how deep the layering goes.
- **Storage, queue, and integration choices** — anything with a vendor or a schema attached.
- **Dependency direction** — anything that introduces a new port, moves a rule across a layer boundary, or would make an inner layer depend on an outer one (a framework, ORM, vendor SDK, or UI library). Direction is the hardest thing on this list to reverse: by the time it is wrong, working code depends on it being wrong.
- **Anything hard to change later** — if reversing the decision would require a migration, a coordinated deploy, a client update, or touching more than a handful of files, it belongs on this list.

Routine work — a bug fix inside an existing pattern, a copy change, adding a field to an existing shape — does not need the ceremony. If you cannot tell which kind of change you are making, treat it as the structural kind and ask.

## What this rule is not

It is not a licence to gold-plate. It does not authorize building for imagined requirements, adding abstraction layers nobody asked for, or expanding scope beyond the request. The bar is **the right decision at the current scope**, argued honestly — not the largest possible decision.
