#!/usr/bin/env node
"use strict";
// Context-budget hook (PostToolUse). Estimates context occupancy from the session
// transcript and, when it crosses CEILING of the model window, writes a RESPAWN
// directive to <project>/PROGRESS.md so the orchestrator checkpoints and a fresh
// session resumes. Never blocks a tool -- advisory via additionalContext.
// Loop sessions only: silent unless the cwd repo has open TASKS.md items.
// One-shot (PHALANX_ONESHOT=1, e.g. the Telegram bot): WARN inline only, never
// write a RESPAWN marker -- there is no fresh-session resumer there.
//
// Occupancy uses the REAL usage signal -- the most recent assistant turn's usage in
// the JSONL transcript (input + cache_read + cache_creation), exactly what the Claude
// Code gauge shows. The old raw-byte estimate (bytes/3.5 of the whole transcript)
// counted the fixed system prompt + CLAUDE.md dump and drifted to ~200% while the
// gauge sat at ~17%, forcing premature checkpoints. Byte estimate is now a fallback;
// window is env-derived (Opus 4.x ~1M), not a hardcoded 200k.
const fs = require("fs");
const path = require("path");
const H = require("./lib/phalanx-hook.js");

// Model context window in tokens. Override per-model via PHALANX_CTX_WINDOW; default
// ~1M (Opus 4.x). Bad/empty/non-positive env -> the safe default.
function ctxWindow() {
  const n = parseInt(process.env.PHALANX_CTX_WINDOW || "", 10);
  return Number.isFinite(n) && n > 0 ? n : 1000000;
}
const WINDOW_TOKENS = ctxWindow();
const CEILING = 0.45;         // never exceed 45%
const WARN = 0.38;            // early nudge to start wrapping the current unit
const CHARS_PER_TOKEN = 3.5;  // fallback-only: rough tokens-per-char for byte estimate
const ONESHOT = process.env.PHALANX_ONESHOT === "1";

const readInput = H.readInput;
const emit = (ctx) => H.emit("PostToolUse", ctx);

// A supervisor (run-work.sh) IS an external fresh-process resumer: when one is
// driving, a ceiling hit must checkpoint + exit, NEVER tell a human to /clear.
const supervisorActive = H.supervisorActive;

// The last assistant turn's usage = the actual prompt size sent = context occupancy
// the gauge shows. Read a bounded tail (trailing tool_result lines can be large) and
// scan complete lines backward for the first message.usage. null when none found.
// ponytail: 1MB tail, not a full-file parse; a trailing entry >~1MB falls back to the
// byte estimate -- rare, and safe now the window is ~1M not 200k.
function lastUsageTokens(tp, size) {
  try {
    const span = Math.min(size, 1024 * 1024);
    if (span <= 0) return null;
    const buf = Buffer.alloc(span);
    const fd = fs.openSync(tp, "r");
    try { fs.readSync(fd, buf, 0, span, size - span); } finally { fs.closeSync(fd); }
    const lines = buf.toString("utf8").split("\n");
    if (size > span) lines.shift(); // drop the leading partial line
    for (let i = lines.length - 1; i >= 0; i--) {
      const ln = lines[i].trim();
      if (!ln || ln[0] !== "{") continue;
      let rec; try { rec = JSON.parse(ln); } catch { continue; }
      const u = rec && rec.message && rec.message.usage;
      if (u) {
        const t = (u.input_tokens || 0) + (u.cache_read_input_tokens || 0) + (u.cache_creation_input_tokens || 0);
        if (t > 0) return t;
      }
    }
  } catch {}
  return null;
}

const input = readInput();
const tp = input.transcript_path || "";
const cwd = input.cwd || process.cwd();
if (!tp || !fs.existsSync(tp)) emit("");

// Only speak in loop sessions -- a repo with open TASKS.md items. Stay silent in
// ordinary interactive sessions so the ceiling nudge isn't noise.
if (H.openTaskCount(cwd) === 0) emit("");

let bytes = 0;
try { bytes = fs.statSync(tp).size; } catch { emit(""); }

// Prefer the real usage signal; fall back to the byte estimate only when the
// transcript has no usage line yet.
const real = lastUsageTokens(tp, bytes);
const estTokens = real != null ? real : Math.round(bytes / CHARS_PER_TOKEN);
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
  // Did a RESPAWN marker already exist before this tool call? If so we've already
  // nudged the human once -- don't re-emit the /clear instruction every subsequent
  // turn (item 5). stop_hook_active (when present) is the same signal: a re-entry.
  let alreadyNudged = !!input.stop_hook_active;
  try { if (/RESPAWN/.test(fs.readFileSync(progress, "utf8").slice(-400))) alreadyNudged = true; } catch {}
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
  // Bare interactive session: nudge to /clear ONCE (gated above); after that just
  // give the terse occupancy line so the instruction doesn't repeat every turn.
  if (alreadyNudged) {
    emit(`Context ~${pct}% (over 45% ceiling). Already checkpointed -- STOP and resume with /work in a fresh session.`);
  }
  emit(`CONTEXT CEILING HIT (~${pct}% >= 45%). Flush remaining task state to PROGRESS.md NOW, then STOP this session. Run /work in a fresh session to resume -- it reads PROGRESS.md first.`);
}

emit(`Context ~${pct}% (ceiling 45%). Finish the current unit, then checkpoint to PROGRESS.md before starting another. Prefer dispatching a subagent over reading files yourself.`);
