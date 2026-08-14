"use strict";
/*
 * core/use-cases/migrate.js — migrate legacy per-mode state files (ADR-0004).
 *
 * The consolidation contract: old state/build.json, state/maintain.json,
 * state/optimize.json (and any stale .claude-state.json) all collapse into the
 * single unified shape in core/domain/state.js. Pure — callers (the CLI /
 * installer) do the fs work.
 */
const { normalizeState, isMode, phasesOf } = require("../domain/phase-machine.js");

// Accept any of the legacy state shapes (they were all { mode, phase, flags })
// plus arbitrary junk; always returns a normalized unified state.
function migrateLegacy(raw) {
  const s = raw && typeof raw === "object" ? raw : {};
  const mode = isMode(s.mode) ? s.mode : "build";
  const phase = phasesOf(mode).includes(s.phase) ? s.phase : phasesOf(mode)[0];
  return normalizeState({ mode, phase, flags: s.flags || {} });
}

// Report what a legacy file would migrate to (used by the CLI's --dry-run).
function diffLegacy(raw) {
  const before = raw || {};
  const after = migrateLegacy(raw);
  return {
    before: { mode: before.mode, phase: before.phase },
    after: { mode: after.mode, phase: after.phase },
    changed: before.mode !== after.mode || before.phase !== after.phase,
  };
}

module.exports = { migrateLegacy, diffLegacy };