"use strict";
/*
 * core/domain/phase-machine.js — the unified phase machine (ADR-0004).
 *
 * Pure, framework-free, zero-dep. Single source of truth for the three MODES
 * (build/maintain/optimize), their ordered PHASES, and each phase's exit gate.
 * No fs/io here — persistence lives in adapters. Deps point inward only.
 *
 * Unified state shape (core/domain/state.js):
 *   { "mode": "build|maintain|optimize", "phase": "<id>", "flags": {} }
 */

// Ordered phases per mode. `memory` is the shared terminal phase across all
// three modes (the GSD/Phalanx/Harold consolidation point).
const MODES = {
  build: [
    "brainstorm", "research", "architecture", "plan", "design",
    "implement", "review", "security", "verify", "commit", "memory",
  ],
  maintain: [
    "comprehend", "characterize", "plan-change",
    "implement", "review", "security", "verify", "commit", "memory",
  ],
  optimize: [
    "baseline", "profile", "hypothesize", "implement",
    "benchmark", "verify", "commit", "memory",
  ],
};

// Shared tail-team metadata for phases that exist identically across modes.
const TAIL = {
  implement: { team: "ponytail + caveman", exit: "code written" },
  review:    { team: "edge-hunter then adversary-review", exit: "findings fixed" },
  security:  { team: "security-review + secret-scan", exit: "clean" },
  verify:    { team: "verify + run + lint + arch-enforce", exit: "all green" },
  commit:    { team: "caveman-commit", exit: "committed" },
  memory:    { team: "consolidate-memory", exit: "synced" },
};

// Phase -> team + exit gate for the mode-specific (head) phases.
const HEAD = {
  brainstorm:   { team: "product-management", exit: "spec exists" },
  research:     { team: "deep-research", exit: "findings" },
  architecture: { team: "system-design + adr-kit", exit: "ADR recorded" },
  plan:         { team: "phased-plan", exit: "plan exists" },
  design:       { team: "frontend-design (3-5 directions first)", exit: "surfaces render" },
  comprehend:   { team: "architecture-map (read-only subagent)", exit: "model built" },
  characterize: { team: "characterization tests around the seam", exit: "seam pinned" },
  "plan-change":{ team: "phased-plan, smallest safe diff", exit: "plan exists" },
  baseline:     { team: "observability capture", exit: "numbers logged" },
  profile:      { team: "profiler/trace", exit: "bottleneck found" },
  hypothesize:  { team: "adr-kit", exit: "ADR recorded" },
  benchmark:    { team: "re-measure vs baseline", exit: "gain proven" },
};

const MODE_NAMES = Object.keys(MODES);

function isMode(mode) { return MODE_NAMES.includes(mode); }

function phasesOf(mode) { return isMode(mode) ? MODES[mode].slice() : null; }

function isValidPhase(mode, phase) {
  const p = phasesOf(mode);
  return p !== null && p.includes(phase);
}

function indexOf(mode, phase) {
  const p = phasesOf(mode);
  return p === null ? -1 : p.indexOf(phase);
}

function firstPhase(mode) { const p = phasesOf(mode); return p ? p[0] : null; }

function lastPhase(mode) { const p = phasesOf(mode); return p ? p[p.length - 1] : null; }

// Next phase in the mode's ordered list; null for the last phase or invalid input.
function nextPhase(mode, phase) {
  const i = indexOf(mode, phase);
  const p = phasesOf(mode);
  if (i === -1) return null;
  return p[i + 1] || null;
}

function prevPhase(mode, phase) {
  const i = indexOf(mode, phase);
  const p = phasesOf(mode);
  if (i === -1) return null;
  return i === 0 ? null : p[i - 1];
}

// Strict pipeline: a transition is only valid to the immediately-next phase.
function canTransition(mode, from, to) {
  return nextPhase(mode, from) === to;
}

function exitGate(mode, phase) {
  if (!isValidPhase(mode, phase)) return null;
  return TAIL[phase] || HEAD[phase] || { team: "?", exit: "?" };
}

// Normalize an arbitrary state object into the unified shape. Unknown modes and
// phases are corrected to a safe default, so callers can feed anything from disk.
function normalizeState(raw) {
  const mode = raw && isMode(raw.mode) ? raw.mode : "build";
  const phase = raw && isValidPhase(mode, raw.phase) ? raw.phase : firstPhase(mode);
  const flags = raw && raw.flags && typeof raw.flags === "object" && !Array.isArray(raw.flags)
    ? raw.flags : {};
  return { mode, phase, flags };
}

module.exports = {
  MODES, MODE_NAMES,
  isMode, phasesOf, isValidPhase, indexOf,
  firstPhase, lastPhase, nextPhase, prevPhase,
  canTransition, exitGate, normalizeState,
};
