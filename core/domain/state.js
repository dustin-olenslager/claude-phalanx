"use strict";
/*
 * core/domain/state.js — the unified project state shape (ADR-0004).
 *
 * The consolidation target: one `.claude-state.json` replaces the old per-mode
 * files (state/build.json, state/maintain.json, state/optimize.json) AND the
 * `.claude-state.json` used by the mode-anchor. Pure. No fs here — see
 * adapters/state/fs.js for read/write.
 */
const { normalizeState } = require("./phase-machine.js");

const STATE_FILE = ".claude-state.json";

// Stringify the unified state with stable key order (mode, phase, flags).
function serialize(state) {
  return JSON.stringify(normalizeState(state), null, 2) + "\n";
}

// Parse + normalize raw text from disk. Never throws — corrupt input degrades
// to the safe default (build/brainstorm) rather than breaking a gate.
function parse(text) {
  try {
    return normalizeState(JSON.parse(text || "{}"));
  } catch {
    return normalizeState({});
  }
}

module.exports = { STATE_FILE, serialize, parse };