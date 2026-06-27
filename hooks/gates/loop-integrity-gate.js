#!/usr/bin/env node
"use strict";
/*
 * Loop-integrity gate (PreToolUse) -- CLAUDE.md v1.4 item 5.
 * Mechanically enforces the autonomous loop's OWN discipline, INDEPENDENT of the
 * (possibly muted) global pipeline gate -- it never reads .pipeline-off:
 *   (a) seed-before-edit    : block a CODE edit when the loop has nothing seeded
 *                             (cwd TASKS.md exists but has 0 open '- [ ]' items).
 *   (b) verify-before-commit: block `git commit` on a task/<slug> branch unless a
 *                             verify/test ran green this pass (cross-pass flag).
 *   (c) merge-on-green       : block a merge INTO main unless the repo opted in
 *                             (.phalanx-automerge) AND the MERGED branch has a fresh
 *                             green verify flag. Non-bypassable (ignores PHALANX_WARN);
 *                             never merge on red. This is the only autonomous path to
 *                             prod authority -- default OFF, per-repo opt-in.
 * Active ONLY in loop-managed repos -- cwd has a TASKS.md. Silent everywhere else,
 * so ordinary repos are untouched. Respects the .work-off kill switch (don't fight
 * an explicit stop). Warn-only under PHALANX_WARN=1 (bot); hard-block otherwise.
 *
 * Verify state is the CROSS-PASS flag (repo+branch keyed under .claude-runs/), which
 * SURVIVES a fresh supervisor pass (new session id) -- the old /tmp/<sid> key did not,
 * so pass N+1 lost the flag and wrongly hard-blocked the commit. SINGLE-WRITER:
 * pipeline-gate.js WRITES the flag (on a verify skill/command); this gate only READS
 * it (H.verifyFlagFresh). Both gates fire on the same Bash event and pipeline-gate is
 * registered first, so a verify recorded earlier (or chained verify && commit) is
 * visible here. A bare verify chained into the same commit command is also accepted
 * inline below, so this gate never depends on hook ordering for the same-command case.
 */
const fs = require("fs");
const path = require("path");
const H = require("./lib/phalanx-hook.js");
const HERE = __dirname;

const readStdin = H.readStdin;
function allow() { process.exit(0); }
const out = (decision, reason) => H.decide("PreToolUse", decision, reason);

const WARN_ONLY = process.env.PHALANX_WARN === "1";

let input = {};
try { input = JSON.parse(readStdin() || "{}"); } catch { allow(); }

const cwd = input.cwd || process.cwd();

// Loop-managed only: a repo with a TASKS.md. Otherwise inert.
let open = 0;
try {
  const t = fs.readFileSync(path.join(cwd, "TASKS.md"), "utf8");
  const m = t.match(/^\s*-\s*\[\s*\]/gm);
  open = m ? m.length : 0;
} catch { allow(); }

// Honor the kill switches -- an explicit stop means don't gate.
if (H.killSwitched(cwd, HERE)) allow();

const tool = input.tool_name || "";
const ti = input.tool_input || {};

const VERIFY_CMD = H.VERIFY_CMD;

if (tool === "Bash") {
  const cmd = (ti.command || "") + "";

  // (c) merge-on-green into main -- the highest-stakes power (autonomous prod authority).
  // Fires only when the merge TARGET is clearly main (already on main, or a checkout/
  // switch main in the same command). Two HARD requirements, BOTH non-bypassable -- this
  // deny IGNORES PHALANX_WARN (unlike 5a/5b), so neither the bot nor a muted pipeline can
  // ever merge unreviewed code: (i) per-repo opt-in .phalanx-automerge, (ii) a fresh GREEN
  // verify for the MERGED branch (checked by source-branch name, since the merge runs FROM
  // main). NEVER merge on red.
  if (H.GIT_MERGE.test(cmd)) {
    const br = H.currentBranch(cwd);
    const intoMain = br === "main" || br === "master" || H.CHECKOUT_MAIN.test(cmd);
    if (intoMain) {
      const root = H.repoRoot(cwd);
      if (!H.autoMergeEnabled(cwd)) {
        return out("deny", "Loop-integrity gate (item 5c): merge into main blocked -- autonomous merge is NOT enabled for this repo. Fix → open a PR for human review (push the task branch, `gh pr create`). To authorize autonomous merge for this repo, the operator creates the marker: `touch " + root + "/.phalanx-automerge` (default OFF; non-bypassable).");
      }
      const src = H.mergedBranch(cmd);
      if (!src || !H.verifyFlagFreshFor(cwd, src)) {
        return out("deny", "Loop-integrity gate (item 5c): merge of '" + (src || "?") + "' into main blocked -- no GREEN verify recorded for that branch this pass. Fix → check out the task branch, run the build/test/lint/typecheck GREEN, then merge. NEVER merges on red (non-bypassable, ignores PHALANX_WARN).");
      }
      // (d) migration safety: a branch that adds/edits a DB migration must NOT auto-merge.
      // Autonomous merge→deploy would ship code whose migration is not yet applied to prod
      // (missing columns → 500s). prod-DB changes stay operator-gated. Non-bypassable.
      if (H.branchTouchesMigration(cwd, src)) {
        return out("deny", "Loop-integrity gate (item 5d): merge of '" + src + "' into main blocked -- it changes a DB migration. Autonomous merge+deploy would ship code whose migration is not yet applied to prod (500s). Fix → apply the migration to prod and sign off, then merge by hand (or open a PR). prod-DB changes are never auto-executed.");
      }
    }
  }

  if (/\bgit\b[^\n]*\bcommit\b/.test(cmd)) {
    const branch = H.currentBranch(cwd);
    // Cross-pass verify flag (written by pipeline-gate) OR a verify chained into this
    // same command -- either satisfies the gate without depending on hook ordering.
    const verified = H.verifyFlagFresh(cwd) || VERIFY_CMD.test(cmd);
    if (/^task\//.test(branch) && !verified) {
      const msg = "Loop-integrity gate (item 5b): commit on " + branch + " blocked -- no verify/test ran green this pass. Fix → run the build/test/lint/typecheck green before committing on a task/<slug> branch (independent of .pipeline-off).";
      return WARN_ONLY ? out("allow", "WARN " + msg) : out("deny", msg);
    }
  }
  allow();
}

if (tool === "Edit" || tool === "Write" || tool === "MultiEdit" || tool === "NotebookEdit") {
  const fp = (ti.file_path || ti.notebook_path || "") + "";
  const isCode = H.CODE.test(fp) && !H.metaRe(HERE).test(fp);
  if (isCode && open === 0) {
    const msg = "Loop-integrity gate (item 5a): edit to " + fp + " blocked -- the loop has no seeded task (0 open items in TASKS.md). Fix → seed the request first: append '- [ ] (req:NEW) <request>' to TASKS.md at the repo root, then retry.";
    return WARN_ONLY ? out("allow", "WARN " + msg) : out("deny", msg);
  }
  allow();
}

allow();
