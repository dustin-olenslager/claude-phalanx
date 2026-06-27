"use strict";
// Standalone (no framework): `node tasks-state.test.js`. Covers the pure TASKS/
// PROGRESS loop-state helpers that the gates + run-work.sh now share.
const assert = require("assert");
const H = require("./phalanx-hook.js");

// openCount
assert.equal(H.openCount(""), 0);
assert.equal(H.openCount("- [ ] a\n- [x] done\n  - [ ] b\n- [X] d"), 2);
assert.equal(H.openCount("no tasks here"), 0);

// respawnActive: present+un-struck within window -> true; struck -> false
assert.equal(H.respawnActive(""), false);
assert.equal(H.respawnActive("RESPAWN now"), true);
assert.equal(H.respawnActive("RESPAWN\nRESPAWN-DONE later"), false);
assert.equal(H.respawnActive("RESPAWN-DONE\nRESPAWN again"), true); // newest RESPAWN un-struck
// far outside the 600-char tail window -> not active
assert.equal(H.respawnActive("RESPAWN" + "x".repeat(700)), false);

// respawnPresent: presence in window, struck or not
assert.equal(H.respawnPresent("RESPAWN-DONE only"), true);
assert.equal(H.respawnPresent("nothing"), false);

// riskLineOf: open task risk first, else progress line, else ""
assert.equal(H.riskLineOf("- [ ] drop table users", ""), "- [ ] drop table users");
assert.equal(H.riskLineOf("- [x] drop table users", ""), ""); // CHECKED task ignored
assert.equal(H.riskLineOf("- [ ] safe work", "note: irreversible cutover ahead"), "note: irreversible cutover ahead");
assert.equal(H.riskLineOf("- [ ] safe", "all fine"), "");

// blockedDirective: only an ACTIVE `BLOCKED:` halt directive -> true; mere prose/
// tables/headers mentioning the word -> false (the nexalog false-halt fix).
assert.equal(H.blockedDirective("### BLOCKED / skipped"), false);
assert.equal(H.blockedDirective("| D2 | (BLOCKED — skipped) |"), false);
assert.equal(H.blockedDirective("the 3 BLOCKED"), false);
assert.equal(H.blockedDirective("was BLOCKED on a table"), false);
assert.equal(H.blockedDirective("- **F1** — BLOCKED: x"), false);
assert.equal(H.blockedDirective("BLOCKED: needs operator"), true);
assert.equal(H.blockedDirective("  BLOCKED: x"), true);
assert.equal(H.blockedDirective("- BLOCKED: x"), true);

// blockedLine: returns the active directive (trimmed), else the word BLOCKED.
assert.equal(H.blockedLine("notes\n  BLOCKED: needs operator\nmore"), "BLOCKED: needs operator");
assert.equal(H.blockedLine("the 3 BLOCKED items"), "BLOCKED");

console.log("ok: tasks-state lib helpers pass");
