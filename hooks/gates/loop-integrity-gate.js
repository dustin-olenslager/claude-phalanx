#!/usr/bin/env node
"use strict";
/*
 * Loop-integrity gate (PreToolUse) -- CLAUDE.md v1.4 item 5.
 * Mechanically enforces the autonomous loop's OWN discipline, INDEPENDENT of the
 * (possibly muted) global pipeline gate -- it never reads .pipeline-off:
 *   (a) seed-before-edit    : block a CODE edit when the loop has nothing seeded
 *                             (cwd TASKS.md exists but has 0 open '- [ ]' items).
 *   (b) verify-before-commit: block `git commit` on a task/<slug> branch unless a
 *                             verify/test ran green this session.
 * Active ONLY in loop-managed repos -- cwd has a TASKS.md. Silent everywhere else,
 * so ordinary repos are untouched. Respects the .work-off kill switch (don't fight
 * an explicit stop). Warn-only under PHALANX_WARN=1 (bot); hard-block otherwise.
 *
 * Verify state is SHARED with pipeline-gate via /tmp/phalanx-pipeline/<sid>, so a
 * test/typecheck/lint recognized by either gate satisfies both -- and we set the
 * flag here too, so verify-before-commit still works when the pipeline gate is off.
 */
const fs = require("fs");
const path = require("path");
const cp = require("child_process");
const H = require("./lib/phalanx-hook.js");
const HERE = __dirname;

const readStdin = H.readStdin;
function allow() { process.exit(0); }
const out = (decision, reason) => H.decide("PreToolUse", decision, reason);

const WARN_ONLY = process.env.PHALANX_WARN === "1";

// Item 3 (gates as teachers): remediation recipes from the policy contract
// (<CLAUDE_DIR>/risk-policy.json); missing file/key -> inline fallback. Read-only:
// never changes whether the gate fires, only the help text.
let POLICY = {};
try { POLICY = JSON.parse(fs.readFileSync(path.join(HERE, "risk-policy.json"), "utf8")); } catch {}
const rx = (k, fallback) => {
  const r = POLICY && POLICY.remediation && POLICY.remediation[k];
  return (typeof r === "string" && r.trim()) ? r : fallback;
};

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
const stateDir = H.stateDir("/tmp/phalanx-pipeline", input.session_id); // shared with pipeline-gate
const { hasFlag, setFlag } = H.flagHelpers(stateDir);
const verified = () => hasFlag("verified");
const setVerified = () => setFlag("verified");

const VERIFY_CMD = H.VERIFY_CMD;

if (tool === "Bash") {
  const cmd = (ti.command || "") + "";
  if (VERIFY_CMD.test(cmd)) setVerified();
  if (/\bgit\b[^\n]*\bcommit\b/.test(cmd)) {
    let branch = "";
    try {
      branch = cp.execFileSync("git", ["rev-parse", "--abbrev-ref", "HEAD"], { cwd, timeout: 3000, stdio: ["ignore", "pipe", "ignore"] }).toString().trim();
    } catch {}
    if (/^task\//.test(branch) && !verified()) {
      const msg = "Loop-integrity gate (item 5b): commit on " + branch + " blocked -- no verify/test ran green this session. " + rx("loop:verify", "Fix → run the build/test/lint/typecheck green this session before committing on a task/<slug> branch (independent of .pipeline-off).");
      return WARN_ONLY ? out("allow", "WARN " + msg) : out("deny", msg);
    }
  }
  allow();
}

if (tool === "Edit" || tool === "Write" || tool === "MultiEdit" || tool === "NotebookEdit") {
  const fp = (ti.file_path || ti.notebook_path || "") + "";
  const isCode = H.CODE.test(fp) && !H.metaRe(HERE).test(fp);
  if (isCode && open === 0) {
    const msg = "Loop-integrity gate (item 5a): edit to " + fp + " blocked -- the loop has no seeded task (0 open items in TASKS.md). " + rx("loop:seed", "Fix → seed the request first: append '- [ ] (req:NEW) <request>' to TASKS.md at the repo root, then retry.");
    return WARN_ONLY ? out("allow", "WARN " + msg) : out("deny", msg);
  }
  allow();
}

allow();
