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
const HERE = __dirname;

function readStdin() { try { return fs.readFileSync(0, "utf8"); } catch { return ""; } }
function allow() { process.exit(0); }
function out(decision, reason) {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: decision, permissionDecisionReason: reason },
  }));
  process.exit(0);
}

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
if (fs.existsSync(path.join(cwd, ".work-off"))) allow();
if (fs.existsSync(path.join(HERE, ".work-off"))) allow();

const tool = input.tool_name || "";
const ti = input.tool_input || {};
const sid = (input.session_id || "nosess").replace(/[^a-zA-Z0-9_-]/g, "");
const stateDir = path.join("/tmp/phalanx-pipeline", sid); // shared with pipeline-gate
const verified = () => { try { return fs.existsSync(path.join(stateDir, "verified")); } catch { return false; } };
const setVerified = () => { try { fs.mkdirSync(stateDir, { recursive: true }); fs.writeFileSync(path.join(stateDir, "verified"), "1"); } catch {} };

const VERIFY_CMD = /(playwright|\be2e\b|vitest|jest|flutter\s+test|pytest|\bgo\s+test\b|cargo\s+test|npm\s+(run\s+)?test|pnpm\s+(run\s+)?test|yarn\s+test|cypress|\btsc\b|--noEmit|typecheck|eslint|biome|\bruff\b|golangci-lint|clippy|\blint\b|depcruise|dependency-cruiser|import-linter|archunit|\bverify\b)/i;

if (tool === "Bash") {
  const cmd = (ti.command || "") + "";
  if (VERIFY_CMD.test(cmd)) setVerified();
  if (/\bgit\b[^\n]*\bcommit\b/.test(cmd)) {
    let branch = "";
    try {
      branch = cp.execFileSync("git", ["rev-parse", "--abbrev-ref", "HEAD"], { cwd, timeout: 3000, stdio: ["ignore", "pipe", "ignore"] }).toString().trim();
    } catch {}
    if (/^task\//.test(branch) && !verified()) {
      const msg = "Loop-integrity gate (item 5b): commit on " + branch + " blocked -- no verify/test ran green this session. Run the build/test/lint/typecheck first (independent of .pipeline-off).";
      return WARN_ONLY ? out("allow", "WARN " + msg) : out("deny", msg);
    }
  }
  allow();
}

if (tool === "Edit" || tool === "Write" || tool === "MultiEdit" || tool === "NotebookEdit") {
  const fp = (ti.file_path || ti.notebook_path || "") + "";
  const CODE = /\.(ts|tsx|mts|cts|js|jsx|mjs|cjs|dart|py|go|rs|java|kt|kts|sql|vue|svelte|rb|php|c|h|cpp|hpp|cs|swift|scala|ex|exs)$/i;
  const esc = HERE.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const META = new RegExp("(^" + esc + "|/\\.claude/|^/tmp/|/node_modules/|/\\.git/|/dist/|/build/)");
  const isCode = CODE.test(fp) && !META.test(fp);
  if (isCode && open === 0) {
    const msg = "Loop-integrity gate (item 5a): edit to " + fp + " blocked -- the loop has no seeded task (0 open items in TASKS.md). Seed the request first: append '- [ ] (req:NEW) <request>' to TASKS.md at the repo root.";
    return WARN_ONLY ? out("allow", "WARN " + msg) : out("deny", msg);
  }
  allow();
}

allow();
