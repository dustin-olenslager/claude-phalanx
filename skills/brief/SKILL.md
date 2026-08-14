---
name: brief
description: >
  Unified BRIEF phase (ADR-0004) — turn a raw request into a structured brief
  and initialize the project's .claude-state.json. First step of the BUILD mode
  machine. Use when starting a new piece of work, at brainstorm, or when the
  user describes what they want built without a spec yet.
license: MIT
---

# brief

Draft the brief, then initialize the unified state machine. The machine is the
single source of truth across modes/phases (build|maintain|optimize).

## Do
1. Capture intent: what the user wants, constraints, success criteria. Keep it
   to a spec-sized statement, not prose.
2. Determine the MODE:
   - empty/near-empty repo → `build`
   - existing code + history → ask one question: "Maintain (change existing) or
     Optimize (perf)?" — never assume.
3. Initialize the state machine via the CLI composition root:
   `node <phalanx>/scripts/phalanx-core.js init --mode <m> --cwd <repo>`
   (or `phalanx-core init --mode <m>` if installed to PATH).
4. Confirm: `node <phalanx>/scripts/phalanx-core.js state --cwd <repo>`

## Exit gate
`spec exists` — a written brief (this session's intent statement) + a valid
`.claude-state.json`. Do NOT advance to research until the spec is captured.

## Next phase
`research` (build) / `comprehend` (maintain) / `baseline` (optimize). Load ONLY
that phase's skill when you get there.
