"use strict";
/*
 * core/use-cases/execute.js — run a phase and check its exit gate.
 * Pure orchestration over the phase machine + a gate predicate the caller
 * supplies (so the use-case stays free of harness/env coupling).
 */
const {
  exitGate, nextPhase, canTransition, normalizeState, isMode,
} = require("../domain/phase-machine.js");

// Gate contract: gate(phase) -> { passed: bool, evidence: string }.
// Returns the next state (phase advanced + flag set) when the exit gate passes,
// or the unchanged state with a reason when it doesn't.
function execute(state, gate) {
  const s = normalizeState(state);
  const g = typeof gate === "function" ? gate(s.phase) : { passed: false, evidence: "" };
  const meta = exitGate(s.mode, s.phase);
  const next = nextPhase(s.mode, s.phase);

  if (!g.passed) {
    return {
      ok: false,
      state: s,
      phase: s.phase,
      reason: g.evidence || `exit gate not met (${meta ? meta.exit : "?"})`,
      complete: false,
    };
  }

  // Phase complete: stamp the flag, advance. Last phase -> done.
  const flags = { ...s.flags, [`${s.phase}:done`]: true };
  if (next === null) {
    return { ok: true, state: { ...s, flags }, phase: s.phase, complete: true };
  }
  return { ok: true, state: { mode: s.mode, phase: next, flags }, phase: next, complete: false };
}

// Convenience: allow a manual phase jump only for valid adjacent forward moves.
function jump(state, target) {
  const s = normalizeState(state);
  if (!isMode(s.mode)) return { ok: false, reason: "unknown mode" };
  if (!canTransition(s.mode, s.phase, target)) {
    return { ok: false, reason: `no transition ${s.mode}:${s.phase} -> ${target}` };
  }
  return { ok: true, state: { mode: s.mode, phase: target, flags: s.flags } };
}

module.exports = { execute, jump };