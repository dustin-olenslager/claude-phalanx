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
 *   (c) merge-on-green       : for the UNATTENDED loop (PHALANX_SUPERVISOR/ONESHOT) only,
 *                             block a merge INTO main unless the repo opted in
 *                             (.phalanx-automerge) AND the MERGED branch has a fresh
 *                             green verify flag. Non-bypassable (ignores PHALANX_WARN);
 *                             never merge on red. This is the only autonomous path to
 *                             prod authority -- default OFF, per-repo opt-in. An
 *                             INTERACTIVE operator (e.g. /ship) IS the human review and is
 *                             exempt; a DB-migration merge is downgraded to a warning.
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

// Loop-managed only: a repo with a TASKS.md. Read at the SHARED repo root (via
// readRepoFile→repoRoot) so a session running inside a worktree counts the SAME backlog
// as the primary checkout. No TASKS.md anywhere -> inert.
const tasksTxt = H.readRepoFile(cwd, "TASKS.md");
if (!tasksTxt) allow();
const open = H.openCount(tasksTxt);

// Kill switches. A GLOBAL stop ($CLAUDE_DIR/.work-off -- outside the agent-writable repo
// tree) disables the whole gate. A REPO-LOCAL cwd/.work-off is honored for the DISCIPLINE
// rules (5a edit-seed, 5b commit-verify) but MUST NOT disable the PROD-AUTHORITY rules
// (5c/5d merge, 5e push): otherwise a loop agent could `touch .work-off` -- a plain Bash
// call nothing blocks -- then merge/push to main, defeating the "non-bypassable" guarantee
// (security audit 2026-08-17). So the prod-authority checks below run regardless of the
// repo-local marker; only 5a/5b consult `repoStopped`.
if (fs.existsSync(path.join(HERE, ".work-off"))) allow();
let repoStopped = false;
try { repoStopped = fs.existsSync(path.join(cwd, ".work-off")); } catch {}

const tool = input.tool_name || "";
const ti = input.tool_input || {};


if (tool === "Bash") {
  const cmd = (ti.command || "") + "";

  // (e) loop-agent push-to-main opt-in: a loop agent (supervisor or one-shot) raw-pushing
  // main without a .phalanx-automerge opt-in is just as unreviewed as a merge. Non-bypassable.
  // A merge (GIT_MERGE) goes through rule 5c and is already opt-in gated; skip if merge present.
  // We strip quoted/heredoc content first so checkpoint writes ('git push origin main' in prose)
  // do not false-fire -- only real shell-level git push commands are caught.
  var loopAgent = process.env.PHALANX_SUPERVISOR === "1" || process.env.PHALANX_ONESHOT === "1";
  if (loopAgent && !H.GIT_MERGE.test(cmd) && H.PUSH_MAIN.test(H.stripQuotedContent(cmd))) {
    var pushTgt = (function() {
      var m = /git\s+-C\s+(\S+)/.exec(cmd);
      return m ? m[1].replace(/^['"]|['"]$/g, "") : cwd;
    }());
    if (!H.autoMergeEnabled(pushTgt)) {
      var pushRoot = H.repoRoot(pushTgt);
      return out("deny", "Loop-integrity gate (item 5e): loop agent push to main blocked -- autonomous push is NOT enabled for " + pushRoot + ". Fix → open a PR instead (`gh pr create`). To authorize autonomous push for this repo, the operator creates the marker: `touch " + pushRoot + "/.phalanx-automerge` (default OFF; non-bypassable).");
    }
  }

    // (c) merge-on-green into main -- the highest-stakes power (autonomous prod authority).
  // Fires only when the merge TARGET is clearly main (already on main, or a checkout/
  // switch main in the same command). Two HARD requirements, BOTH non-bypassable -- this
  // deny IGNORES PHALANX_WARN (unlike 5a/5b), so neither the bot nor a muted pipeline can
  // ever merge unreviewed code: (i) per-repo opt-in .phalanx-automerge, (ii) a fresh GREEN
  // verify for the MERGED branch (checked by source-branch name, since the merge runs FROM
  // main). NEVER merge on red.
  if (H.GIT_MERGE.test(cmd)) {
    // The merge may run in cwd OR in a `-C <primary>` target (the worktree-land form,
    // where the primary stays on main). Resolve the TARGET tree + its branch so a land
    // from a worktree (cwd is on the task branch) is still caught as into-main.
    const tgt = H.mergeCwdPath(cmd) || cwd;
    const br = H.currentBranch(tgt);
    const intoMain = br === "main" || br === "master" || H.CHECKOUT_MAIN.test(cmd);
    if (intoMain) {
      const root = H.repoRoot(cwd);
      const src = H.mergedBranch(cmd);
      // Scope the HARD prod-authority gate to the UNATTENDED loop (supervisor / one-shot),
      // matching rule 5e's loopAgent guard above. An INTERACTIVE operator running /ship IS
      // the human review -- blocking the operator's own merge was the over-reach. The
      // autonomous path stays fully gated: opt-in marker + fresh GREEN verify + migration block.
      if (loopAgent) {
        if (!H.autoMergeEnabled(cwd)) {
          return out("deny", "Loop-integrity gate (item 5c): autonomous merge into main blocked -- autonomous merge is NOT enabled for this repo. Fix → open a PR for human review (push the task branch, `gh pr create`). To authorize autonomous merge for this repo, the operator creates the marker: `touch " + root + "/.phalanx-automerge` (default OFF; non-bypassable). (Interactive operator /ship is exempt -- this fires only for the PHALANX_SUPERVISOR/ONESHOT loop.)");
        }
        if (!src || !H.verifyFlagFreshFor(cwd, src)) {
          return out("deny", "Loop-integrity gate (item 5c): merge of '" + (src || "?") + "' into main blocked -- no GREEN verify recorded for that branch this pass. Fix → check out the task branch, run the build/test/lint/typecheck GREEN, then merge. NEVER merges on red (non-bypassable, ignores PHALANX_WARN).");
        }
        // (d) migration safety: a branch that adds/edits a DB migration must NOT auto-merge.
        // Autonomous merge→deploy would ship code whose migration is not yet applied to prod
        // (missing columns → 500s). prod-DB changes stay operator-gated. Non-bypassable.
        if (H.branchTouchesMigration(cwd, src)) {
          return out("deny", "Loop-integrity gate (item 5d): merge of '" + src + "' into main blocked -- it changes a DB migration. Autonomous merge+deploy would ship code whose migration is not yet applied to prod (500s). Fix → apply the migration to prod and sign off, then merge by hand (or open a PR). prod-DB changes are never auto-executed.");
        }
      } else if (src && H.branchTouchesMigration(cwd, src)) {
        // INTERACTIVE operator: do NOT block the operator's own merge, but surface the
        // prod-DB migration risk so the deploy step doesn't ship unapplied columns (500s).
        return out("allow", "Loop-integrity gate (item 5d, interactive): heads up -- '" + src + "' changes a DB migration. Apply it to prod BEFORE you deploy, or you'll ship code whose columns don't exist yet (500s). Proceeding because you are driving interactively.");
      }
    }
  }

  // Scan the command that RUNS, not the data it carries: this tested the raw string, so a
  // quoted argument merely CONTAINING the words fired the gate -- the same class c9293ea
  // fixed in secret-gate. And resolve the repo the command actually targets: a hook is
  // handed the SESSION cwd, so a `cd <other repo> && ...` prefix was gated against the
  // wrong branch and read the wrong verify flag.
  if (!repoStopped && /\bgit\b[^\n]*\bcommit\b/.test(H.stripQuotedContent(cmd))) {
    const gcwd = H.effectiveCwd(cmd, cwd);
    const branch = H.currentBranch(gcwd);
    // Cross-pass verify flag, written by `phalanx-verify` on a real exit 0 and DELETED on
    // any non-zero exit. The old `|| VERIFY_CMD.test(cmd)` escape hatch is gone: it matched
    // the COMMIT COMMAND ITSELF, so `git commit -m "fix: verify the tree"` (or any message
    // containing verify/lint/e2e/test) satisfied its own gate. Nothing about a command's
    // text is evidence that anything passed -- only an exit code is.
    const verified = H.verifyFlagFresh(gcwd);
    if (/^task\//.test(branch) && !verified) {
      const msg = "Loop-integrity gate (item 5b): commit on " + branch + " blocked -- no verify/test exited 0 for this branch. Fix → run it through the recorder so the exit code is what counts: `" + require('path').join(HERE,'bin','phalanx-verify') + " pnpm verify` (or the same wrapper around your build/test/lint/typecheck command), then retry. A bare run, or a verify word in the commit message, no longer counts (independent of .pipeline-off).";
      return WARN_ONLY ? out("allow", "WARN " + msg) : out("deny", msg);
    }
  }
  allow();
}

if (tool === "Edit" || tool === "Write" || tool === "MultiEdit" || tool === "NotebookEdit") {
  if (repoStopped) allow();
  const fp = (ti.file_path || ti.notebook_path || "") + "";
  const isCode = H.CODE.test(fp) && !H.metaRe(HERE).test(fp);
  if (isCode && open === 0) {
    const msg = "Loop-integrity gate (item 5a): edit to " + fp + " blocked -- the loop has no seeded task (0 open items in TASKS.md). Fix → seed the request first: append '- [ ] (req:NEW) <request>' to TASKS.md at the repo root, then retry.";
    return WARN_ONLY ? out("allow", "WARN " + msg) : out("deny", msg);
  }
  allow();
}

allow();
