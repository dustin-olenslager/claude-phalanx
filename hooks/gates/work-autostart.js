#!/usr/bin/env node
"use strict";
// SessionStart hook: auto-start the autonomous work loop when a repo has open
// TASKS.md items -- no /work command needed. Silenced by either kill switch:
//   <repo>/.work-off   (per-repo)   or   <CLAUDE_DIR>/.work-off (global)
const fs = require("fs");
const path = require("path");

const CLAUDE_DIR = __dirname;

function emit(ctx) {
  if (ctx) process.stdout.write(JSON.stringify({
    hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: ctx },
  }));
  process.exit(0);
}
function readInput() {
  try { return JSON.parse(fs.readFileSync(0, "utf8") || "{}"); }
  catch { return {}; }
}

const input = readInput();
const cwd = input.cwd || process.cwd();

if (fs.existsSync(path.join(cwd, ".work-off"))) emit("");
if (fs.existsSync(path.join(CLAUDE_DIR, ".work-off"))) emit("");

const tasks = path.join(cwd, "TASKS.md");
let open = 0;
try {
  const txt = fs.readFileSync(tasks, "utf8");
  const m = txt.match(/^\s*-\s*\[\s*\]/gm);
  open = m ? m.length : 0;
} catch { emit(""); }
if (open === 0) emit("");

let resume = "";
try {
  const p = fs.readFileSync(path.join(cwd, "PROGRESS.md"), "utf8");
  if (/RESPAWN/.test(p)) resume = " A RESPAWN checkpoint exists in PROGRESS.md -- resume from it first.";
  if (/BLOCKED/.test(p)) emit("AUTONOMOUS LOOP paused: PROGRESS.md has a BLOCKED line. Surface the blocker to the user and wait -- do not auto-start.");
} catch {}

emit(
  `AUTONOMOUS LOOP ACTIVE -- ${open} open task(s) in TASKS.md.${resume} ` +
  `Begin the /work loop now WITHOUT waiting for a command: read PROGRESS.md (resume) then TASKS.md, ` +
  `spawn the orchestrator subagent, work the top task to green (build/test pass), commit on a task/<slug> branch, ` +
  `check it off, continue to the next. Honor all gates and the 45% context ceiling (checkpoint+respawn on RESPAWN). ` +
  `To stop: user says "stop loop", or touch ./.work-off (this repo) or ${CLAUDE_DIR.replace(/\\/g,"/")}/.work-off (everywhere).`
);
