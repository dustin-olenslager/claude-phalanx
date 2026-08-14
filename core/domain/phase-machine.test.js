"use strict";
// Standalone: `node core/domain/phase-machine.test.js`. Pure domain tests.
const assert = require("assert");
const M = require("./phase-machine.js");

// modes/phases
assert.deepStrictEqual(M.MODE_NAMES, ["build", "maintain", "optimize"]);
assert.strictEqual(M.isMode("build"), true);
assert.strictEqual(M.isMode("nope"), false);
assert.deepStrictEqual(M.phasesOf("build").slice(-1), ["memory"]);
assert.strictEqual(M.phasesOf("maintain").length, 9);
assert.strictEqual(M.phasesOf("optimize").length, 8);

// validation
assert.strictEqual(M.isValidPhase("build", "architecture"), true);
assert.strictEqual(M.isValidPhase("build", "comprehend"), false); // build-only
assert.strictEqual(M.isValidPhase("maintain", "comprehend"), true);
assert.strictEqual(M.isValidPhase("optimize", "baseline"), true);
assert.strictEqual(M.isValidPhase("build", "baseline"), false);

// navigation
assert.strictEqual(M.firstPhase("build"), "brainstorm");
assert.strictEqual(M.lastPhase("build"), "memory");
assert.strictEqual(M.nextPhase("build", "architecture"), "plan");
assert.strictEqual(M.nextPhase("build", "memory"), null);
assert.strictEqual(M.nextPhase("build", "zzz"), null);
assert.strictEqual(M.prevPhase("build", "plan"), "architecture");
assert.strictEqual(M.prevPhase("build", "brainstorm"), null);

// strict pipeline transitions
assert.strictEqual(M.canTransition("build", "plan", "design"), true);
assert.strictEqual(M.canTransition("build", "plan", "implement"), false); // skip
assert.strictEqual(M.canTransition("maintain", "characterize", "plan-change"), true);
assert.strictEqual(M.canTransition("optimize", "benchmark", "verify"), true);

// exit gates — shared tail + mode head
assert.deepStrictEqual(M.exitGate("build", "commit"), { team: "caveman-commit", exit: "committed" });
assert.deepStrictEqual(M.exitGate("maintain", "security"), { team: "security-review + secret-scan", exit: "clean" });
assert.deepStrictEqual(M.exitGate("optimize", "profile"), { team: "profiler/trace", exit: "bottleneck found" });
assert.strictEqual(M.exitGate("build", "nonsense"), null);

// normalizeState: safe defaults + passthrough
assert.deepStrictEqual(M.normalizeState({}), { mode: "build", phase: "brainstorm", flags: {} });
assert.deepStrictEqual(M.normalizeState({ mode: "maintain" }), { mode: "maintain", phase: "comprehend", flags: {} });
assert.deepStrictEqual(M.normalizeState({ mode: "bogus", phase: "x", flags: { a: 1 } }),
  { mode: "build", phase: "brainstorm", flags: { a: 1 } });
assert.deepStrictEqual(M.normalizeState({ mode: "optimize", phase: "benchmark", flags: { y: 2 } }),
  { mode: "optimize", phase: "benchmark", flags: { y: 2 } });
assert.deepStrictEqual(M.normalizeState({ mode: "build", phase: "research", flags: [1, 2] }),
  { mode: "build", phase: "research", flags: {} }); // non-object flags dropped

console.log("ok: phase-machine passes");