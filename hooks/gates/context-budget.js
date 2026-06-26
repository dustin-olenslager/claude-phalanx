#!/usr/bin/env node
"use strict";
// Context-budget hook (PostToolUse). Estimates accumulated context from the
// session transcript and, when it crosses CEILING of the model window, writes a
// RESPAWN directive to <project>/PROGRESS.md so the orchestrator checkpoints and
// a fresh session resumes. Never blocks a tool -- advisory via additionalContext.
// Loop sessions only: silent unless the cwd repo has open TASKS.md items.
// One-shot (PHALANX_ONESHOT=1, e.g. the Telegram bot): WARN inline only, never
// write a RESPAWN marker -- there is no fresh-session resumer there.
const fs = require("fs");
const path = require("path");

const WINDOW_TOKENS = 200000; // 200k window
const CEILING = 0.45;         // never exceed 45%
const WARN = 0.38;            // early nudge to start wrapping the current unit
const CHARS_PER_TOKEN = 3.5;  // conservative estimate
const ONESHOT = process.env.PHALANX_ONESHOT === "1";

function readInput() {
  try { return JSON.parse(fs.readFileSync(0, "utf8") || "{}"); }
  catch { return {}; }
}
function emit(ctx) {
  if (ctx) process.stdout.write(JSON.stringify({
    hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: ctx },
  }));
  process.exit(0);
}

// A supervisor (run-work.sh) IS an external fresh-process resumer: when one is
// driving, a ceiling hit must checkpoint + exit, NEVER tell a human to /clear.
// Detected by the env the supervisor exports to each pass, or a live pidfile.
function supervisorActive(dir) {
  if (process.env.PHALANX_SUPERVISOR === "1") return true;
  try {
    const pid = parseInt(fs.readFileSync(path.join(dir, ".claude-runs", "supervisor.pid"), "utf8").trim(), 10);
    if (pid > 0) { process.kill(pid, 0); return true; }
  } catch {}
  return false;
}

const input = readInput();
const tp = input.transcript_path || "";
const cwd = input.cwd || process.cwd();
if (!tp || !fs.existsSync(tp)) emit("");

// Only speak in loop sessions -- a repo with open TASKS.md items. Stay silent in
// ordinary interactive sessions so the ceiling nudge isn't noise.
let openTasks = 0;
try {
  const t = fs.readFileSync(path.join(cwd, "TASKS.md"), "utf8");
  const m = t.match(/^\s*-\s*\[\s*\]/gm);
  openTasks = m ? m.length : 0;
} catch {}
if (openTasks === 0) emit("");

let bytes = 0;
try { bytes = fs.statSync(tp).size; } catch { emit(""); }

const estTokens = Math.round(bytes / CHARS_PER_TOKEN);
const frac = estTokens / WINDOW_TOKENS;

if (frac < WARN) emit(""); // healthy, say nothing

const progress = path.join(cwd, "PROGRESS.md");
const pct = (frac * 100).toFixed(0);

if (frac >= CEILING) {
  const SUP = supervisorActive(cwd);
  // Write the RESPAWN checkpoint marker only when a resumer exists: a supervisor
  // pass (relaunched fresh) OR an interactive session (a human reopens). NEVER
  // under a bare one-shot run (no resumer) -- keeps the item-6 invariant.
  const willResume = SUP || !ONESHOT;
  if (willResume) {
    const line = `\n<!-- RESPAWN ${new Date().toISOString()} ctx~${pct}% -- checkpoint state above, STOP, resume fresh -->\n`;
    try {
      if (!fs.existsSync(progress)) fs.writeFileSync(progress, "# PROGRESS\n");
      const tail = fs.readFileSync(progress, "utf8").slice(-400);
      if (!/RESPAWN/.test(tail)) fs.appendFileSync(progress, line);
    } catch {}
  }
  if (SUP) {
    // The supervisor relaunches a fresh `claude -p` pass that reads PROGRESS.md.
    emit(`CONTEXT CEILING HIT (~${pct}% >= 45%). Checkpoint remaining task state to PROGRESS.md NOW and STOP this pass -- the supervisor will relaunch a fresh pass that resumes from PROGRESS.md. No human action needed; do not tell anyone to reset context manually.`);
  }
  if (ONESHOT) {
    emit(`CONTEXT CEILING HIT (~${pct}% >= 45%) on a one-shot run with no supervisor. Wrap up the current task and report now; do not start more work. (No RESPAWN written -- no resumer in one-shot mode.)`);
  }
  emit(`CONTEXT CEILING HIT (~${pct}% >= 45%). Flush remaining task state to PROGRESS.md NOW, then STOP this session. Run /work in a fresh session to resume -- it reads PROGRESS.md first.`);
}

emit(`Context ~${pct}% (ceiling 45%). Finish the current unit, then checkpoint to PROGRESS.md before starting another. Prefer dispatching a subagent over reading files yourself.`);
