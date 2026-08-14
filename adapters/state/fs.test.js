"use strict";
// Standalone: `node adapters/state/fs.test.js`. Uses a temp dir.
const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const S = require("./fs.js");
const { STATE_FILE } = require("../../core/domain/state.js");

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "phalanx-state-"));
try {
  // missing file -> safe default
  assert.deepStrictEqual(S.read(dir), { mode: "build", phase: "brainstorm", flags: {} });

  // write + read round-trip
  S.write(dir, { mode: "optimize", phase: "baseline", flags: {} });
  assert.deepStrictEqual(S.read(dir), { mode: "optimize", phase: "baseline", flags: {} });
  assert.strictEqual(fs.existsSync(path.join(dir, STATE_FILE)), true);

  // write normalizes garbage
  S.write(dir, { mode: "bogus" });
  assert.deepStrictEqual(S.read(dir), { mode: "build", phase: "brainstorm", flags: {} });

  // corrupt file -> safe default, never throws
  fs.writeFileSync(path.join(dir, STATE_FILE), "{not json", "utf8");
  assert.deepStrictEqual(S.read(dir), { mode: "build", phase: "brainstorm", flags: {} });
} finally {
  fs.rmSync(dir, { recursive: true, force: true });
}

console.log("ok: state fs adapter passes");