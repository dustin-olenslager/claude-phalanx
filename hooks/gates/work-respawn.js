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

const input = readInput();
const cwd = input.cwd || process.cwd();

const ONESHOT = process.env.PHALANX_ONESHOT === "1";
if (ONESHOT) stop();

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
