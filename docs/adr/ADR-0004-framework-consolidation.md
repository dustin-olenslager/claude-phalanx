# ADR-0004 — Consolidate GSD / Phalanx / Harold into one clean-architecture framework

- **Status:** Accepted (2026-08-14) — implemented in `core/` + `adapters/` + `scripts/phalanx-core.js`
- **Deciders:** Operator, Phalanx maintainer
- **Relates to:** [ADR-0001](ADR-0001-autonomous-merge-deploy-on-green.md), [ADR-0002](ADR-0002-merge-deploy-safety-hardening.md), [ADR-0003](ADR-0003-worktree-isolation.md)

## Context

Three systems are currently maintained in parallel, each solving one layer of the
same stack, each with its own conventions, state format, and install surface:

| System | Layer | Current artifacts |
|---|---|---|
| **Harold** | Memory / chief-of-staff — CRM, operational state files, knowledge vault, cross-session recall | `harold.works` framework: task layer (Linear), CRM (L2), ops state files (L3), Obsidian vault (L4) |
| **GSD** | Engineering workflow — context-engineering, spec-driven phase loop | `gsd-core` (`ROADMAP.md`, `STATE.md`, `CONTEXT.md`), 34 subagents, workflows, `gsd-tools` CLI |
| **Phalanx** (this repo) | Execution harness — phase-gated factory, gates, hooks, adversarial review, token discipline | `.claude-state.json`, `PROMPT.md`, hooks/gates, skills, ADRs |

The three overlap on the *phase pipeline* concept (Harold's day-rhythm ↔ GSD's
five-step loop ↔ Phalanx's mode/phase machine), but diverge on everything else:
memory format, agent roster, state files, and enforcement mechanism (Claude
hooks vs. opencode plugins vs. plain workflows). Maintaining three means three
installers, three state schemas, and three places a phase can advance.

The goal: **one framework** with a clean-architecture core that is
provider-agnostic (Claude Code, opencode, Codex, future tools) and
model-agnostic (Anthropic, OpenRouter, DeepSeek, Ollama, future), so that
"upgrade" means swapping an adapter — never rewriting the core.

## Decision

Consolidate into a single repo (this one) with a **ports & adapters (hexagonal)
layout**. The core is pure, file-based, and tool-agnostic; every external concern
lives behind a port and is satisfied by a swappable adapter.

### Target layout

```
claude-phalanx/
├── core/                        # pure, framework-agnostic (no Claude/opencode imports)
│   ├── domain/                  # entities + value objects
│   │   ├── phase.machine.ts     # modes (build/maintain/optimize) + phase transitions
│   │   ├── task.ts              # unified task entity (GSD task ↔ Harold ticket)
│   │   ├── memory-item.ts       # one-fact memory entity (Harold vault item)
│   │   └── decision.ts          # ADR entity (GSD decision ↔ Harold decision log)
│   ├── use-cases/               # orchestration logic, framework-agnostic
│   │   ├── brief.ts             # morning/status brief (Harold rhythm)
│   │   ├── plan.ts              # spec-driven planning (GSD)
│   │   ├── execute.ts           # phase-gated execution (Phalanx)
│   │   ├── verify.ts            # green-verify + gates (Phalanx)
│   │   └── recall.ts            # memory query/synthesis (Harold vault)
│   └── ports/                   # interfaces only
│       ├── memory-store.ts      # vault / state-file persistence
│       ├── task-store.ts        # Linear / GitHub / file backlog
│       ├── model-router.ts      # provider + model resolution
│       ├── orchestrator.ts      # spawn/monitor subagents (any tool)
│       └── gate-keeper.ts       # enforce/soften mechanical gates
├── adapters/
│   ├── memory/                  # impl of memory-store
│   │   ├── obsidian.ts          # Harold L4 vault (Obsidian)
│   │   ├── jsonl.ts             # plain-file memory (portable default)
│   │   └── sqlite.ts            # optional structured store
│   ├── tasks/
│   │   ├── linear.ts            # Harold task layer
│   │   ├── github.ts            # GitHub issues / PRs
│   │   └── files.ts             # markdown backlog (GSD TASKS.md)
│   ├── models/
│   │   ├── anthropic.ts         # Claude (sonnet/opus/haiku)
│   │   ├── openrouter.ts
│   │   ├── deepseek.ts
│   │   ├── ollama.ts            # local (qwen3-coder:30b etc.)
│   │   └── router.policy.ts     # quality|balanced|budget profile → concrete model
│   ├── orchestrators/
│   │   ├── claude-code.ts       # claude -p / subagents (current harness)
│   │   ├── opencode.ts          # opencode subagents + TUI
│   │   └── phalanx-cli.ts       # multi-agent team spawn/monitor
│   └── gates/
│       ├── claude-hooks.ts      # PreToolUse/Stop hooks (current)
│       └── opencode-plugin.ts   # opencode permission/plugin gates
├── skills/                      # thin, phase-scoped skills → call core use-cases
├── agents/                      # reduced roster, each one a thin adapter over a use-case
├── state/                       # per-mode templates for .claude-state.json
├── docs/adr/                    # ADRs (decision log = core/use-cases/decide)
└── install.sh / install.ps1     # installs core + picks adapters per target tool
```

### Unified state format

One machine-readable state file per project replaces the parallel formats:

```jsonc
// .claude-state.json (extended)
{
  "mode": "build",                 // build | maintain | optimize
  "phase": "implement",            // current phase id
  "flags": {},
  "memory": {                      // Harold layers, unified
    "vaultPath": "~/notes/obsidian", // L4 (or omit → jsonl adapter)
    "taskStore": "linear"            // L1 (linear|github|files)
  },
  "workflow": {                    // GSD loop, unified
    "loop": "discuss-plan-execute-verify-ship",
    "artifacts": ["ROADMAP.md", "STATE.md"]
  }
}
```

### Unified phase machine

GSD's five-step loop and Harold's daily rhythm collapse into Phalanx's existing
mode/phase machine; `discuss` and `memory` become first-class phases in every mode:

- **BUILD:** brainstorm → discuss → research → architecture → plan → design →
  implement → review → security → verify → commit → memory
- **MAINTAIN:** comprehend → characterize → plan-change → discuss → implement →
  review → security → verify → commit → memory
- **OPTIMIZE:** baseline → profile → hypothesize → implement → benchmark →
  verify → commit → memory

`memory` (Harold) is now the *persistent* phase: every phase's exit-gate updates
the vault (task state, decision, facts), and `brief` (morning) + `recall`
(query) are the always-available entry points.

### Model routing as policy, not code

Model choice moves out of agents and prompts into `router.policy.ts`:

```ts
// profile: quality   → anthropic/claude-sonnet, heavy: anthropic/claude-opus
// profile: balanced  → openrouter/auto, heavy: deepseek/deepseek-v4-pro
// profile: budget    → ollama/qwen3-coder:30b, heavy: openrouter/auto
```

Changing models, or adding a provider, is a config change — core never edits.

### Ports over providers

Every current Phalanx/GSD/Harold integration that touches an external system
becomes a port + adapter. The Claude-specific hooks (`hooks/`) remain one
adapter (target: Claude Code); an opencode plugin adapter (`adapters/gates/
opencode-plugin.ts`) provides the same gates for opencode; the orchestrator
adapter lets the same core drive either tool's subagent system.

## Rollback / migration

- **No data loss:** existing `~/.claude` install, `gsd-core`, and any Harold
  vault are left untouched; new state is written alongside, with a one-time
  `migrate` use-case importing `ROADMAP.md`/`STATE.md`/vault into the unified
  format.
- **Phase-by-phase:** consolidate *memory* first (Harold's value is additive and
  low-risk), then *workflow* (GSD loop as core use-cases), then *harness*
  (gates/adapters). Any layer can stop early without breaking the others.
- **Kill switches:** existing `.pipeline-off`, `.ts-arch-off`, `.secret-scan-off`
  and `PHALANX_WARN=1` semantics are preserved through the gate-keeper port.

## Consequences

**Positive:** one installer, one state schema, one phase machine; model/provider
upgrades are adapter swaps; the same core drives Claude Code, opencode, and
future tools; Harold's memory becomes durable for every workflow, not just its own.

**Negative / accepted:** consolidation is a port, not a merge — the 34 GSD agents
and Claude-specific hooks are reduced/adapted, losing some fidelity; `gsd-tools`
CLI dependency is dropped in favor of core use-cases (behavior preserved, not the
binary); Obsidian becomes one memory adapter among several, weakening its
"single source of truth" posture for anyone who wants it.

## Verification

- `core/` has zero imports from any tool SDK (enforced by a lint gate).
- Each port has ≥1 adapter and a contract test; every adapter passes the same
  suite.
- `migrate` import round-trips a real `ROADMAP.md`/`STATE.md` + a Harold vault
  sample into unified state, lossless.
- Phase machine: state transition tests for all three modes incl. `discuss` and
  `memory` entry/exit gates.
- Same task executed end-to-end under the Claude-code adapter and the opencode
  adapter produces equivalent phase outcomes.

## Implementation notes (2026-08-14)

- Implemented in **plain CommonJS, zero-dep** to honor the repo's "zero deps,
  runtime node only" badge — not TypeScript. `*.ts` paths in the target layout
  above map to `.js` equivalents.
- `core/domain/phase-machine.js` — the three modes + ordered phases + exit gates,
  all pure (matching PROMPT.md STEP 1/2).
- `core/use-cases/{brief,plan,execute,recall,migrate}.js` — orchestration; ports
  injected by the caller (no fs/io in core).
- `core/ports/model-router.js` — pure escalation policy; `adapters/models/
  router-policy.js` maps quality|balanced|budget → concrete provider+model.
- `adapters/memory/{jsonl,obsidian}.js` + `adapters/state/fs.js` — concrete stores
  behind the memory-store contract (`store(dir)` object shape).
- `scripts/phalanx-core.js` — composition root + CLI (`init/next/jump/plan/route/
  recall/add-memory/migrate`).
- `scripts/run-tests.js` — discovers + runs every standalone `*.test.js`
  (`node scripts/run-tests.js`).
- install.sh copies `core/` + `adapters/` to `$CLAUDE_DIR/phalanx-core/` and puts
  the CLI at `$CLAUDE_DIR/bin/phalanx-core`.
- Deferred (per phase-by-phase migration): `discuss` as a first-class phase,
  Linear/GitHub task adapters, sqlite memory, opencode plugin gate. These extend
  the same ports without touching core.
- Tests: `node scripts/run-tests.js` — phase-machine, execute, migrate, state fs,
  jsonl + obsidian memory, router-policy (all green).