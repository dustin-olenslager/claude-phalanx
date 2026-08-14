"use strict";
// Standalone: `node adapters/memory/jsonl.test.js`. Uses a temp dir.
const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const J = require("./jsonl.js");

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "phalanx-mem-"));
try {
  // add + normalize
  const a = J.add(dir, { name: "Deploy Auth", type: "project", summary: "OAuth headless token", content: "details here" });
  assert.strictEqual(a.name, "Deploy Auth");
  assert.strictEqual(a.type, "project");
  assert.strictEqual(J.add(dir, { name: "Data Loss", type: "feedback", summary: "never wipe prod" }).type, "feedback");

  // all
  assert.strictEqual(J.all(dir).length, 2);

  // search case-insensitive over summary/content
  assert.strictEqual(J.search(dir, "oauth").length, 1);
  assert.strictEqual(J.search(dir, "prod").length, 1);
  assert.strictEqual(J.search(dir, "zzz").length, 0);
  assert.strictEqual(J.search(dir, "").length, 2);

  // remove by slug
  assert.strictEqual(J.remove(dir, "Data Loss"), true);
  assert.strictEqual(J.remove(dir, "Missing"), false);
  assert.strictEqual(J.all(dir).length, 1);

  // corrupt lines skipped, not fatal
  fs.appendFileSync(path.join(dir, "memory.jsonl"), "not-json\n", "utf8");
  assert.strictEqual(J.all(dir).length, 1);

  // unknown type normalized to reference
  const c = J.add(dir, { name: "Odd", type: "bogus" });
  assert.strictEqual(c.type, "reference");
} finally {
  fs.rmSync(dir, { recursive: true, force: true });
}

console.log("ok: jsonl memory adapter passes");