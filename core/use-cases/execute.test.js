"use strict";
// Standalone: `node core/use-cases/execute.test.js`.
const assert = require("assert");
const { execute, jump } = require("./execute.js");

// gate met -> advance with flag stamped
const always = () => ({ passed: true, evidence: "test" });
const r1 = execute({ mode: "build", phase: "plan" }, always);
assert.strictEqual(r1.ok, true);
assert.strictEqual(r1.state.phase, "design");
assert.strictEqual(r1.state.flags["plan:done"], true);

// gate not met -> unchanged, reason, not complete
const never = () => ({ passed: false, evidence: "nope" });
const r2 = execute({ mode: "build", phase: "plan" }, never);
assert.strictEqual(r2.ok, false);
assert.strictEqual(r2.state.phase, "plan");
assert.ok(r2.reason);

// last phase -> complete, no advance
const r3 = execute({ mode: "build", phase: "memory" }, always);
assert.strictEqual(r3.ok, true);
assert.strictEqual(r3.complete, true);
assert.strictEqual(r3.state.phase, "memory");

// exit-gate reason reflects the machine when evidence empty
const r4 = execute({ mode: "optimize", phase: "baseline" }, () => ({ passed: false, evidence: "" }));
assert.ok(/exit gate not met/.test(r4.reason));

// jump: only valid adjacent forward
assert.strictEqual(jump({ mode: "build", phase: "plan" }, "design").ok, true);
assert.strictEqual(jump({ mode: "build", phase: "plan" }, "implement").ok, false); // skip
assert.strictEqual(jump({ mode: "build", phase: "plan" }, "brainstorm").ok, false); // backward

// normalize garbage input
assert.strictEqual(execute(null, always).ok, true);
assert.strictEqual(execute("junk", always).state.mode, "build");

console.log("ok: execute use-case passes");