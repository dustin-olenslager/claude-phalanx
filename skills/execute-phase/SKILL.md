---
name: execute-phase
description: >
  Unified EXECUTE driver (ADR-0004) — run the current phase, check its exit
  gate, and advance the unified state machine. Use when work is underway in any
  mode and the current phase's deliverable is done (or claimed done) and needs
  to be promoted to the next phase.
license: MIT
---

# execute-phase

Run the active phase to its exit gate, then advance. The machine is read from
`.claude-state.json`; the CLI is the only writer, so the state stays canonical
across harnesses (Claude Code, opencode, supervisors).

## Do
1. Read current state: `node <phalanx>/scripts/phalanx-core.js state --cwd <repo>`
2. Verify the CURRENT phase's exit gate is genuinely met:
   - brainstorm → spec exists
   - research → findings
   - architecture → ADR recorded
   - plan → plan exists
   - implement → code written
   - review → findings fixed
   - security → clean
   - verify → all green
   - commit → committed
   (mode-specific heads: comprehend→model built, characterize→seam pinned,
   plan-change→plan exists, baseline→numbers logged, profile→bottleneck found,
   hypothesize→ADR recorded, benchmark→gain proven)
3. Advance: `node <phalanx>/scripts/phalanx-core.js next --cwd <repo>`
   The CLI re-checks the exit gate (`<phase>:done` flag or an installed
   `hooks/gates/exit-<phase>.js`) and refuses to advance when it isn't met.
4. If the gate legitimately blocks you, do the phase's real work, re-run, then
   advance. Do NOT force a jump (`jump <phase>`) except for explicitly trivial
   work or operator override.

## Exit gate
The phase actually advanced (state shows the next phase) or the machine reported
`complete`.

## Note
For trivial work (typo, one-liner, config tweak, no auth/security/public-API/
data-model touch) you may skip phases and jump straight to verify + commit under
the caveman rules — that is the load-bearing token-economy escape hatch.
