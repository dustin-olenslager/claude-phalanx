"use strict";
/*
 * core/use-cases/plan.js — derive an ordered plan from a brief + mode.
 * Pure. Turns a brief into the concrete phase list with exit gates, so the
 * agent knows exactly what "done" means at each step (exit-gate discipline).
 */
const { phasesOf, exitGate } = require("../domain/phase-machine.js");

// plan({ brief, mode }) -> { mode, phases: [{id, team, exit}] }
function plan(brief, mode) {
  const m = (mode && MODE_OK(mode)) ? mode : "build";
  const phases = phasesOf(m).map((id) => ({ id, ...exitGate(m, id) }));
  return {
    brief: brief && brief.title ? brief.title : "untitled",
    mode: m,
    phases,
  };
}

function MODE_OK(m) { return ["build", "maintain", "optimize"].includes(m); }

module.exports = { plan };