"use strict";
// Standalone: `node core/use-cases/migrate.test.js`.
const assert = require("assert");
const { migrateLegacy, diffLegacy } = require("./migrate.js");

// legacy per-mode files all had { mode, phase, flags } — collapse to unified
assert.deepStrictEqual(migrateLegacy({ mode: "build", phase: "research", flags: { x: 1 } }),
  { mode: "build", phase: "research", flags: { x: 1 } });
assert.deepStrictEqual(migrateLegacy({ mode: "maintain", phase: "characterize" }),
  { mode: "maintain", phase: "characterize", flags: {} });
assert.deepStrictEqual(migrateLegacy({ mode: "optimize", phase: "benchmark" }),
  { mode: "optimize", phase: "benchmark", flags: {} });

// junk / partial -> safe default
assert.deepStrictEqual(migrateLegacy(undefined), { mode: "build", phase: "brainstorm", flags: {} });
assert.deepStrictEqual(migrateLegacy({ mode: "nope", phase: "x" }), { mode: "build", phase: "brainstorm", flags: {} });
assert.deepStrictEqual(migrateLegacy({ mode: "build", phase: "bogus" }), { mode: "build", phase: "brainstorm", flags: {} });

// diff
assert.strictEqual(diffLegacy({ mode: "build", phase: "brainstorm" }).changed, false);
assert.strictEqual(diffLegacy({ mode: "nope" }).changed, true);

console.log("ok: migrate use-case passes");