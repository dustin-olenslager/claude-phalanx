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

// ── merge-on-green helpers (rule 5c) ───────────────────────────────────────
// mergedBranch: pull the SOURCE branch out of a `git merge ...`, skipping flags +
// `-m <msg>`, never returning the target (main/master). Pure string parsing.
assert.equal(H.mergedBranch("git checkout main && git merge --no-ff task/x"), "task/x");
assert.equal(H.mergedBranch("git merge --no-ff task/slug -m \"msg\""), "task/slug");
assert.equal(H.mergedBranch("git merge -m \"msg\" task/y"), "task/y"); // -m value not mistaken for branch
assert.equal(H.mergedBranch("git merge main"), "");                    // target only, no source
assert.equal(H.mergedBranch("echo no merge here"), "");

// GIT_MERGE / CHECKOUT_MAIN / PUSH_MAIN matchers.
assert.equal(H.GIT_MERGE.test("git merge --no-ff task/x"), true);
assert.equal(H.GIT_MERGE.test("git commit -m x"), false);
assert.equal(H.CHECKOUT_MAIN.test("git checkout main && git merge task/x"), true);
assert.equal(H.CHECKOUT_MAIN.test("git switch master"), true);
assert.equal(H.CHECKOUT_MAIN.test("git checkout task/x"), false);
assert.equal(H.PUSH_MAIN.test("git push origin main"), true);
assert.equal(H.PUSH_MAIN.test("git push origin task/x"), false);

// GIT_MERGE must match the `git merge` SUBCOMMAND only (v1.6.7 false-positive fix).
assert.equal(H.GIT_MERGE.test("git checkout main && git merge --no-ff task/x"), true);
assert.equal(H.GIT_MERGE.test("git merge task/x"), true);
assert.equal(H.GIT_MERGE.test("git checkout -b task/merge-ui"), false);   // branch name, not subcommand
assert.equal(H.GIT_MERGE.test('git commit -m "prep for merge"'), false);  // commit message
assert.equal(H.GIT_MERGE.test("git switch feature/merge-stuff"), false);

// migration-path detection (rule 5d): keep migration-bearing branches out of auto-merge.
assert.equal(H.pathsTouchMigration(["src/app.ts", "drizzle/0020_x.sql"]), true);
assert.equal(H.pathsTouchMigration(["prisma/migrations/20240101_x/migration.sql"]), true);
assert.equal(H.pathsTouchMigration(["db/migrate/0003.py"]), true);
assert.equal(H.pathsTouchMigration(["src/migrations.ts"]), false);        // not under a migrations/ dir
assert.equal(H.pathsTouchMigration(["src/a.ts", "README.md"]), false);
assert.equal(H.pathsTouchMigration([]), false);

console.log("ok: tasks-state lib helpers pass");
