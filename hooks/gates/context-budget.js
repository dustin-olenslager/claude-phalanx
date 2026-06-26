#!/usr/bin/env node
"use strict";
// Context-budget hook (PostToolUse). Estimates accumulated context from the
// session transcript and, when it crosses CEILING of the model window, writes a
// RESPAWN directive to <project>/PROGRESS.md so the orchestrator checkpoints and
// a fresh session resumes. Never blocks a tool -- advisory via additionalContext.
const fs = require("fs");
const path = require("path");

const WINDOW_TOKENS = 200000; // 200k window
const CEILING = 0.45;         // never exceed 45%
const WARN = 0.38;            // early nudge to start wrapping the current unit
const CHARS_PER_TOKEN = 3.5;  // conservative estimate

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

const input = readInput();
const tp = input.transcript_path || "";
const cwd = input.cwd || process.cwd();
if (!tp || !fs.existsSync(tp)) emit("");

let bytes = 0;
try { bytes = fs.statSync(tp).size; } catch { emit(""); }

const estTokens = Math.round(bytes / CHARS_PER_TOKEN);
const frac = estTokens / WINDOW_TOKENS;

if (frac < WARN) emit(""); // healthy, say nothing

const progress = path.join(cwd, "PROGRESS.md");
const pct = (frac * 100).toFixed(0);

if (frac >= CEILING) {
  const line = `\n<!-- RESPAWN ${new Date().toISOString()} ctx~${pct}% -- checkpoint state above, STOP, resume fresh -->\n`;
  try {
    if (!fs.existsSync(progress)) fs.writeFileSync(progress, "# PROGRESS\n");
    const tail = fs.readFileSync(progress, "utf8").slice(-400);
    if (!/RESPAWN/.test(tail)) fs.appendFileSync(progress, line);
  } catch {}
  emit(`CONTEXT CEILING HIT (~${pct}% >= 45%). Flush remaining task state to PROGRESS.md NOW, then STOP this session. Run /work in a fresh session to resume -- it reads PROGRESS.md first.`);
}

emit(`Context ~${pct}% (ceiling 45%). Finish the current unit, then checkpoint to PROGRESS.md before starting another. Prefer dispatching a subagent over reading files yourself.`);
