# Token & Context Discipline

A drop-in operating standard for agents that read context files: `CLAUDE.md`, `AGENTS.md`, `.cursorrules`, `.windsurfrules`, `.github/copilot-instructions.md`, `GEMINI.md`, Crush rules, Codex `AGENTS.md`, etc.

Distilled from the 2025–2026 canon: Anthropic's *Effective Context Engineering for AI Agents* and *Effective Harnesses for Long-Running Agents*, the Anthropic Skills authoring guide and the cookbook on memory/compaction/clearing, the Microsoft `agent-skills` progressive-disclosure pattern, the `caveman`/`spartan` output-compression skills, the `token-optimizer` ghost-token analysis, and the lazy-loading patterns from `claude-token-efficient` and `claude-token-optimizer`.

Compose with — do not replace — your existing `AGENTS.md`. This file owns one concern: making every token earn its place, in service of better output, not just cheaper output.

---

## North Star

**Find the smallest set of high-signal tokens that maximizes the likelihood of the desired outcome.**

Everything below serves that one rule. Context is a budget, not a backpack. Attention degrades with length — context rot, lost-in-the-middle, U-shaped recall — so fewer tokens often means *better* answers, not just cheaper ones. Quality and economy point the same direction.

## I. Input discipline — what you load

**1. The largest line item is invisible.** A fresh session can start at 50–70K tokens before the user types: system prompt, tool definitions, MCP servers, skills, memory files. Every one of those rides every message and counts toward rate limits whether cached or not. If the runtime exposes `/context`, `ccusage`, or equivalent, measure first; trim before optimizing anything else.

**2. Just-in-time beats just-in-case.** Prefer references (file paths, queries, URIs, line ranges) over the underlying content. Load the file when the task hits the file, not before. `glob`, `grep`, and `view` are cheaper than preloading directories. Letting the agent retrieve is a feature of the harness, not a fallback for missing context.

**3. Progressive disclosure is the contract.** Three tiers, always:
- **Tier 1** — name + one-line description, always loaded (~80 tokens). This is the activation signal.
- **Tier 2** — the body of the instruction file, loaded when triggered (<5,000 tokens, <500 lines).
- **Tier 3** — `references/`, `assets/`, `scripts/`, loaded only when Tier 2 explicitly says to.

The activation condition lives in the description, never in the body. The body loads *after* the trigger fires; if "when to use" is buried inside, the agent can never read it in time to decide.

**4. Persistent context must justify its rent.** A `CLAUDE.md` or `AGENTS.md` is paid for on every turn. If it grows past the value it adds, it is a tax. Audit quarterly: delete what the model already knows (basic syntax, common APIs, what a PDF is), keep what it cannot infer (project conventions, soft-delete columns, ID aliasing across services, the gotchas that bit you last week).

**5. Compose, don't centralize.** Global rules at `~/.claude/CLAUDE.md` (or platform equivalent), project rules at the project root, subsystem rules in subdirectory `CLAUDE.md` files. Scope each rule to where it bites. A rule that ships in every session for one rare subsystem is overpaying.

**6. Bundled content is free until read.** Reference docs, API specs, full schemas, large datasets — all zero cost on the filesystem until the agent opens them. Be generous with what you *bundle*, austere with what you *autoload*.

---

## II. Output discipline — what you say

**7. Match length to information.** A two-line answer for a two-line question. A paragraph when synthesis is required. No throat-clearing, no recap of the prompt, no "Sure, I'd be happy to help." Compression is not curtness; it is respect for the reader's attention budget too.

**8. Brevity is not a quality tax.** The March 2026 paper *Brevity Constraints Reverse Performance Hierarchies in Language Models* found constrained-brief outputs improved accuracy by up to 26 percentage points on certain benchmarks and reversed model rankings outright. Verbose ≠ thorough. Saying less, deliberately, makes models smarter.

**9. Drop to full prose when ambiguity is dangerous.** Specifically: security warnings, irreversible actions (`rm -rf`, `DROP TABLE`, `git push --force`, prod deploys), multi-step sequences where order matters, and moments when the user is visibly confused or repeating a question. Everywhere else, telegraphic prose wins.

**10. Code, paths, commands, URLs, versions, and identifiers pass through untouched.** Compression is a prose concern. Never rewrite a file path, never paraphrase an error message, never abbreviate a CLI flag. Compress the *explanation around* the artifact, never the artifact.

**11. Templates beat descriptions.** When the output has a fixed shape, give the model the shape directly — a fenced template, a JSON skeleton, a column list. Pattern-matching against a concrete structure is more reliable than parsing prose instructions about that structure.

**12. Skip obvious next steps.** Do not append "Let me know if you have any questions" or "You may also want to consider…" unless invited. Unsolicited suggestions cost tokens, dilute the actual answer, and signal bot.

---

## III. Tool discipline

**13. Every tool justifies its existence.** Tools should be self-contained, non-overlapping, intuitively scoped. If a human engineer cannot tell which of two tools to call in a given situation, the agent will not do better. The failure mode of a toolset is overlap, not under-coverage; prune accordingly.

**14. Tool descriptions are the API.** They are what the model sees at decision time. Write them like docstrings the model will actually read: what the tool does, when to call it, what each parameter means, what comes back. Concrete, specific, no marketing.

**15. Scripts beat generated code for deterministic work.** A `validate_form.py` that returns "OK" or a structured error consumes ~5 tokens on success. Asking the model to generate equivalent validation inline costs hundreds and is non-deterministic. For anything done more than twice the same way, write a script and let the agent invoke it. Script output is the only part that hits context.

**16. Use fully qualified MCP tool names.** `Service:tool_name`, not `tool_name`. Bare names ambiguate when multiple servers expose similar tools, and the model's recovery path is to guess.

---

## IV. Memory and long-horizon discipline

**17. Compaction is not free.** When a conversation summarizes itself, 60–70% of detail is typically lost per pass; after two or three compactions, you have effectively restarted. Plan for it. The agent that knows it will be compacted writes durable artifacts on the way (progress files, decision records, test results) instead of trusting the summary to preserve them.

**18. Bridge files outlive context windows.** For multi-session work, maintain one of: `progress.md`, `claude-progress.txt`, `decisions/`, or equivalent. Each session ends by updating it; each new session starts by reading it plus `git log`. This is the single highest-leverage intervention for long-horizon agent reliability — Anthropic's own harness guidance is built on this pattern.

**19. Initializer ≠ executor.** The first session on a new project should set up the environment, write the requirements doc, and seed the bridge file — and stop. Subsequent sessions execute against that scaffolding. Mixing the two roles into one prompt is the most common cause of premature "done" and one-shot apps that miss the spec.

**20. Externalize state you do not need to reason over.** If the agent only needs to *find* something later, store an identifier, not the content. Filesystem, sqlite, a notes file — anywhere outside the context window — beats stuffing it back into the prompt.

---

## V. Multi-agent and subagent discipline

**21. Subagents are context isolation, not just parallelism.** The reason to spawn a subagent is to give a focused task a fresh, narrow context and receive back only its synthesis. The parent stays uncluttered. Use subagents when a task would otherwise dump 20K+ tokens of intermediate work into the main thread.

**22. Right model for the work.** Routers exist because using a frontier model for "rename this variable across the file" is waste. Smaller/faster models for mechanical work; larger ones reserved for architectural reasoning and ambiguity. If the harness supports model selection, use it.

**23. Curate examples, do not enumerate edge cases.** Few-shot is powerful; an edge-case dump is not. Three diverse, canonical examples beat fifteen near-duplicates every time. An example earns its place when it teaches something the other examples don't.

---

## VI. Anti-patterns — do not do these

- Don't dump the whole repo into context "just in case." Use `grep`/`glob`.
- Don't restate the user's question before answering. They wrote it; they know it.
- Don't acknowledge instructions ("Got it, I will now…"). Just do the thing.
- Don't apologize for length, then write a long response anyway.
- Don't leave dead context loaded. If a skill or file is no longer relevant, `/clear` and start fresh.
- Don't write `# adds two numbers` above `def add(a, b)`. Comments that restate code are pure cost.
- Don't include rationale the user didn't ask for. "I chose React because…" — only if asked.
- Don't optimize before measuring. Without a baseline, every "improvement" is theater.

---

## VII. Measurement — so the rest of this is real, not vibes

Baseline: capture a fresh-session token count and a representative end-of-session count. Re-measure after any change to `CLAUDE.md`, MCP servers, skills, or hook configuration.

The honest comparison is *this rule set vs. terse-but-unstructured*, not *this rule set vs. an unconstrained verbose model* — the latter conflates the discipline with generic compression and overstates the win.

When in doubt, the rule that resolves the tie is the North Star: **smallest set of high-signal tokens that maximizes likelihood of the desired outcome.** If anything in this file fails that test for your workload, delete it. This file is not exempt from its own rules.
