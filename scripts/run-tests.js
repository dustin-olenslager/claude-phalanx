#!/usr/bin/env node
"use strict";
/*
 * scripts/run-tests.js — discover + run every standalone *.test.js in the repo.
 * Zero-dep: just spawns `node <file>` per test and aggregates failures.
 *   node scripts/run-tests.js            # run all
 *   node scripts/run-tests.js core       # only under core/
 */
const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const filter = process.argv[2] || "";

const files = [];
(function walk(dir) {
  if (dir.includes(path.sep + ".git")) return;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) walk(full);
    else if (e.name.endsWith(".test.js") && full.includes(filter)) files.push(full);
  }
})(root);

if (!files.length) { console.log("no tests found" + (filter ? ` (filter: ${filter})` : "")); process.exit(1); }

let failed = 0;
for (const f of files) {
  try {
    execFileSync(process.execPath, [f], { stdio: "inherit" });
  } catch {
    console.log(`FAIL ${path.relative(root, f)}`);
    failed++;
  }
}
console.log(`\n${files.length - failed}/${files.length} tests passed`);
process.exit(failed ? 1 : 0);