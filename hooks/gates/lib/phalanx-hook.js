"use strict";
/*
 * Shared primitives for the Phalanx hook gates. Each gate is installed FLATTENED
 * into CLAUDE_DIR root (install.sh `cp hooks/gates/*.js -> CLAUDE_DIR/`), with this
 * file alongside under CLAUDE_DIR/lib/. Gates require it as `./lib/phalanx-hook.js`
 * so the path resolves identically in-repo and installed (and in the self-test's
 * per-gate temp copies, which install.sh seeds with a sibling lib/).
 *
 * These are the verbatim primitives that were duplicated inline across the gates;
 * behavior is unchanged. Where trivial wording differed, the strictest existing
 * form was kept (noted below).
 */
const fs = require("fs");
const path = require("path");
const cp = require("child_process");

// stdin reader + JSON parse. readStdin() returns raw text (""); readInput() parses
// to an object ({}). Both swallow errors, matching every gate's inline version.
function readStdin() {
  try { return fs.readFileSync(0, "utf8"); } catch { return ""; }
}
function readInput() {
  try { return JSON.parse(fs.readFileSync(0, "utf8") || "{}"); }
  catch { return {}; }
}

// hookSpecificOutput envelope writers, then exit 0. emit() = additionalContext
// hooks (SessionStart / PostToolUse / UserPromptSubmit); decide() = PreToolUse
// permission gates. Both no-op the write when there is nothing to say.
function emit(hookEventName, ctx) {
  if (ctx) process.stdout.write(JSON.stringify({
    hookSpecificOutput: { hookEventName, additionalContext: ctx },
  }));
  process.exit(0);
}
function decide(hookEventName, permissionDecision, permissionDecisionReason) {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: { hookEventName, permissionDecision, permissionDecisionReason },
  }));
  process.exit(0);
}

// Count open `- [ ]` items in cwd/TASKS.md. Missing/unreadable file -> 0
// (the autostart/intent/context-budget reading). Gates that must go inert when
// TASKS.md is wholly absent keep that branch in their own policy.
function openTaskCount(cwd) {
  return openCount(readRepoFile(cwd, "TASKS.md"));
}

// ── Single source of truth for TASKS.md / PROGRESS.md loop state ───────────
// Replaces the ad-hoc regex re-parses that were duplicated across the gates and
// run-work.sh (mirrored in scripts/tasks-state.sh). Pure helpers take text so they
// are unit-testable; tasksState(cwd) is the thin fs reader over them.

// First task/progress line matching a data-risk / irreversible-change phrase.
const RISK = /(data[- ]?loss|data[- ]?continuity|irreversible|(won'?t|will ?not) be (in|captured)|(can'?t|cannot) be undone|drop\s+(table|column|database)|delete[sd]?\s+prod|destructive|truncate\b|migration cutover|cutover|backfill|\bwipe\b)/i;
// Standard tail window for scanning append-only PROGRESS.md for the RESPAWN marker.
const RESPAWN_WINDOW = 600;

function readRepoFile(cwd, name) {
  try { return fs.readFileSync(path.join(cwd, name), "utf8"); } catch { return ""; }
}

// Count of open `- [ ]` items in TASKS.md text.
function openCount(tasksText) {
  const m = (tasksText || "").match(/^\s*-\s*\[\s*\]/gm);
  return m ? m.length : 0;
}

// A RESPAWN checkpoint is ACTIVE only when the most recent RESPAWN within the
// standard tail window is not already struck by a later RESPAWN-DONE.
function respawnActive(progressText) {
  const p = progressText || "";
  return /RESPAWN/.test(p.slice(-RESPAWN_WINDOW)) && p.lastIndexOf("RESPAWN-DONE") < p.lastIndexOf("RESPAWN");
}

// A RESPAWN marker is merely PRESENT in the standard tail window (used to suppress
// a repeat nudge — distinct from respawnActive's un-struck question).
function respawnPresent(progressText) {
  return /RESPAWN/.test((progressText || "").slice(-RESPAWN_WINDOW));
}

// First open `- [ ]` task (TASKS.md) — else any line (PROGRESS.md) — flagged risky.
function riskLineOf(tasksText, progressText) {
  for (const l of (tasksText || "").split(/\r?\n/)) {
    if (/^\s*-\s*\[\s*\]/.test(l) && RISK.test(l)) return l.trim();
  }
  for (const l of (progressText || "").split(/\r?\n/)) {
    if (RISK.test(l)) return l.trim();
  }
  return "";
}

// The unified reader. blocked scans the WHOLE PROGRESS.md (a verbose pass must not
// push the BLOCKED line out of a tail window); the rest use the helpers above.
function tasksState(cwd) {
  const tasks = readRepoFile(cwd, "TASKS.md");
  const progress = readRepoFile(cwd, "PROGRESS.md");
  return {
    open: openCount(tasks),
    blocked: /BLOCKED/.test(progress),
    respawn: respawnActive(progress),
    riskLine: riskLineOf(tasks, progress),
  };
}

// Kill switches: per-repo cwd/.work-off OR global CLAUDE_DIR/.work-off.
function killSwitched(cwd, claudeDir) {
  try {
    if (fs.existsSync(path.join(cwd, ".work-off"))) return true;
    if (fs.existsSync(path.join(claudeDir, ".work-off"))) return true;
  } catch {}
  return false;
}

// A supervisor (run-work.sh) is driving when PHALANX_SUPERVISOR=1 or a live
// pidfile exists under dir/.claude-runs/supervisor.pid.
function supervisorActive(dir) {
  if (process.env.PHALANX_SUPERVISOR === "1") return true;
  try {
    const pid = parseInt(fs.readFileSync(path.join(dir, ".claude-runs", "supervisor.pid"), "utf8").trim(), 10);
    if (pid > 0) { process.kill(pid, 0); return true; }
  } catch {}
  return false;
}

// Session-scoped flag dir + helpers under base/<sanitized session id>.
function stateDir(base, sessionId) {
  const sid = (sessionId || "nosess").replace(/[^a-zA-Z0-9_-]/g, "");
  return path.join(base, sid);
}
function flagHelpers(dir) {
  const flag = (n) => path.join(dir, n);
  return {
    flag,
    hasFlag: (n) => { try { return fs.existsSync(flag(n)); } catch { return false; } },
    setFlag: (n) => { try { fs.mkdirSync(dir, { recursive: true }); fs.writeFileSync(flag(n), "1"); } catch {} },
  };
}

// Cross-pass "verify ran green" flag, keyed on repo + branch (NOT session id) and
// stored under the repo's own .claude-runs/, so a fresh supervisor pass (new session
// id) still sees a verify that an earlier pass on the same branch recorded. This is
// the fix for the cross-pass verify bug: the old /tmp/<sid> key vanished on relaunch
// and hard-blocked the pass-N+1 commit.
//
// SINGLE-WRITER contract: only pipeline-gate.js WRITES it (markVerified) -- on a
// verify skill or a verify command. loop-integrity-gate.js only READS it
// (verifyFlagFresh). Both gates fire on the same Bash event, so pipeline-gate's
// write precedes loop-integrity's read within the turn.
function repoRoot(cwd) {
  try {
    return cp.execFileSync("git", ["rev-parse", "--show-toplevel"], { cwd, timeout: 3000, stdio: ["ignore", "pipe", "ignore"] }).toString().trim() || cwd;
  } catch { return cwd; }
}
function currentBranch(cwd) {
  try {
    return cp.execFileSync("git", ["rev-parse", "--abbrev-ref", "HEAD"], { cwd, timeout: 3000, stdio: ["ignore", "pipe", "ignore"] }).toString().trim();
  } catch { return ""; }
}
const VERIFY_FLAG_TTL_MS = 12 * 60 * 60 * 1000; // a stale flag older than 12h is ignored + swept
function verifyFlagPath(cwd) {
  const root = repoRoot(cwd);
  const branch = (currentBranch(cwd) || "nobranch").replace(/[^a-zA-Z0-9_.-]/g, "_");
  return path.join(root, ".claude-runs", "verified." + branch);
}
function sweepStaleVerifyFlags(cwd) {
  try {
    const dir = path.join(repoRoot(cwd), ".claude-runs");
    for (const f of fs.readdirSync(dir)) {
      if (!f.startsWith("verified.")) continue;
      const p = path.join(dir, f);
      try { if (Date.now() - fs.statSync(p).mtimeMs > VERIFY_FLAG_TTL_MS) fs.unlinkSync(p); } catch {}
    }
  } catch {}
}
function markVerified(cwd) {
  try {
    const p = verifyFlagPath(cwd);
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, new Date().toISOString());
  } catch {}
}
function verifyFlagFresh(cwd) {
  sweepStaleVerifyFlags(cwd);
  try {
    const st = fs.statSync(verifyFlagPath(cwd));
    return Date.now() - st.mtimeMs <= VERIFY_FLAG_TTL_MS;
  } catch { return false; }
}

// Build the META exclusion regex anchored at a gate's own install dir (HERE), so a
// gate never fires on its own tree, .claude/, /tmp, node_modules, .git, dist, build.
function metaRe(here) {
  const esc = here.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp("(^" + esc + "|/\\.claude/|^/tmp/|/node_modules/|/\\.git/|/dist/|/build/)");
}

// Source-file extensions treated as "code" by the edit gates.
const CODE = /\.(ts|tsx|mts|cts|js|jsx|mjs|cjs|dart|py|go|rs|java|kt|kts|sql|vue|svelte|rb|php|c|h|cpp|hpp|cs|swift|scala|ex|exs)$/i;
// TypeScript subset (effect-ca-gate).
const TS = /\.(ts|tsx|mts|cts)$/i;
// Commands that count as a verify (test runner / typecheck / lint / arch / e2e).
const VERIFY_CMD = /(playwright|\be2e\b|vitest|jest|flutter\s+test|pytest|\bgo\s+test\b|cargo\s+test|npm\s+(run\s+)?test|pnpm\s+(run\s+)?test|yarn\s+test|cypress|\btsc\b|--noEmit|typecheck|eslint|biome|\bruff\b|golangci-lint|clippy|\blint\b|depcruise|dependency-cruiser|import-linter|archunit|\bverify\b)/i;

module.exports = {
  readStdin, readInput,
  emit, decide,
  openTaskCount, killSwitched, supervisorActive,
  RISK, RESPAWN_WINDOW, readRepoFile, openCount,
  respawnActive, respawnPresent, riskLineOf, tasksState,
  stateDir, flagHelpers, metaRe,
  repoRoot, currentBranch, markVerified, verifyFlagFresh,
  CODE, TS, VERIFY_CMD,
};
