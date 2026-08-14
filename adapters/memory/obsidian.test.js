"use strict";
// Standalone: `node adapters/memory/obsidian.test.js`. Uses a temp vault.
const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const O = require("./obsidian.js");

const vault = fs.mkdtempSync(path.join(os.tmpdir(), "phalanx-vault-"));
try {
  O.add(vault, { name: "Loop Integrity", type: "project", summary: "single-writer rule", content: "one writer per repo" });
  O.add(vault, { name: "Merge on Green", type: "project", summary: "opt-in", content: "green or deny", tags: ["git", "safety"] });

  assert.strictEqual(O.all(vault).length, 2);

  // search
  assert.strictEqual(O.search(vault, "single-writer").length, 1);
  assert.strictEqual(O.search(vault, "green").length, 1);
  assert.strictEqual(O.search(vault, "git").length, 1); // tag search
  assert.strictEqual(O.search(vault, "zzz").length, 0);

  // file is kebab-case md with frontmatter
  assert.ok(fs.existsSync(path.join(vault, "loop-integrity.md")));
  const txt = fs.readFileSync(path.join(vault, "loop-integrity.md"), "utf8");
  assert.ok(/^---\ntype: project\nsummary:/.test(txt));

  // slug collision -> same file
  assert.strictEqual(O.filePath(vault, "Loop Integrity"), O.filePath(vault, "loop_integrity"));
} finally {
  fs.rmSync(vault, { recursive: true, force: true });
}

console.log("ok: obsidian memory adapter passes");