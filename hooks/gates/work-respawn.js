#!/usr/bin/env node
"use strict";
// Stop hook: in-session respawn driver. When Claude finishes a turn during an
// active loop, decide whether to continue. Works in Desktop/CLI/IDE alike -- no
// external process needed.
// One-shot (PHALANX_ONESHOT=1, e.g. the Telegram bot): suppressed entirely --
// the orchestrator's in-run loop drives the single seeded task to green within
// one run; no cross-turn continuation, no backlog walking.
const fs = require("fs");
const path = require("path");

const CLAUDE_DIR = __dirname;

function cont(reason) {
  process.stdout.write(JSON.stringify({ decision: "block", reason }));
  process.exit(0);
}
function stop() { process.exit(0); }
function readInput() {
  try { return JSON.parse(fs.readFileSync(0, "utf8") || "{}"); }
  catch { return {}; }
}

// A supervisor (run-work.sh) relaunches fresh `claude -p` passes itself; when one
// is live, this session must just END (the supervisor continues) -- never block to
// drive the same session on, and never emit a "/clear" instruction (item 4).
function supervisorActive(dir) {
  if (process.env.PHALANX_SUPERVISOR === "1") return true;
  try {
    const pid = parseInt(fs.readFileSync(path.join(dir, ".claude-runs", "supervisor.pid"), "utf8").trim(), 10);
    if (pid > 0) { process.kill(pid, 0); return true; }
  } catch {}
  return false;
}

// On a context-ceiling RESPAWN in a bare interactive session (no supervisor yet),
// hand off to a detached supervisor instead of asking a human to /clear -- it
// relaunches fresh `claude -p` passes from PROGRESS.md until the backlog is done.
function launchSupervisor(dir) {
  const sup = path.join(CLAUDE_DIR, "supervisord.sh");
  try {
    if (!fs.existsSync(sup)) return false;
    const ch = require("child_process").spawn("bash", [sup, "start", "-r", dir], {
      detached: true, stdio: "ignore", cwd: dir,
    });
    ch.unref();
    return true;
  } catch { return false; }
}

const input = readInput();
const cwd = input.cwd || process.cwd();

const ONESHOT = process.env.PHALANX_ONESHOT === "1";
if (ONESHOT) stop();
if (supervisorActive(cwd)) stop();

// Guard against infinite loops.
if (input.stop_hook_active) stop();

if (fs.existsSync(path.join(cwd, ".work-off"))) stop();
if (fs.existsSync(path.join(CLAUDE_DIR, ".work-off"))) stop();

const tasks = path.join(cwd, "TASKS.md");
let open = 0;
try {
  const txt = fs.readFileSync(tasks, "utf8");
  const m = txt.match(/^\s*-\s*\[\s*\]/gm);
  open = m ? m.length : 0;
} catch { stop(); }
if (open === 0) stop();

try {
  const p = fs.readFileSync(path.join(cwd, "PROGRESS.md"), "utf8");
  if (/BLOCKED/.test(p.slice(-600))) stop();
} catch {}

let respawn = false;
try {
  const p = fs.readFileSync(path.join(cwd, "PROGRESS.md"), "utf8");
  respawn = /RESPAWN/.test(p.slice(-600));
} catch {}

if (respawn) {
  // Auto-escalate: launch a detached supervisor to carry the loop to done with no
  // human /clear. (No supervisor is active -- supervisorActive() stopped us above.)
  // Fall back to the manual nudge only if the supervisor can't be launched.
  if (launchSupervisor(cwd)) stop();
  cont(
    `Context ceiling was hit. You've checkpointed to PROGRESS.md. Run /clear to reset context, ` +
    `then resume the /work loop from PROGRESS.md. ${open} task(s) remain. Do not summarize -- just continue.`
  );
}

cont(
  `Autonomous loop still active -- ${open} open task(s) remain in TASKS.md. ` +
  `Finish ONLY the task you are on and its verify; do not start another backlog item mid-turn. ` +
  `When it is green and checked off, pull the next. Do not stop to ask unless genuinely BLOCKED ` +
  `(then write BLOCKED: <reason> to PROGRESS.md). No end-of-turn summary -- keep working.`
);
