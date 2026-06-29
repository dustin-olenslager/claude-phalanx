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
// Code gauge shows. When no usage line exists yet we skip the nudge for this turn
// rather than guess from raw bytes (the old bytes/3.5 estimate counted the fixed
// system prompt + CLAUDE.md dump and drifted to ~200% while the gauge sat at ~17%).
// Window is env-derived (Opus 4.x ~1M), not a hardcoded 200k.
const fs = require("fs");
const path = require("path");
const H = require("./lib/phalanx-hook.js");

// Context window in tokens, SENSED from the model on the last assistant turn (read from
// the transcript) -- the operator runs different models with different windows, so a fixed
// default is wrong. PHALANX_CTX_WINDOW overrides explicitly. Unknown model -> the standard
// 200k Claude window: a too-SMALL guess only makes the ceiling fire earlier (safe); a
// too-LARGE guess lets a run blow past the real limit and degrade (the bug being fixed).
function windowForModel(model) {
  const env = parseInt(process.env.PHALANX_CTX_WINDOW || "", 10);
  if (Number.isFinite(env) && env > 0) return env;          // explicit override wins
  const m = String(model || "").toLowerCase();
  if (!m) return 200000;
  if (/1m|context-1m|\[1m\]/.test(m)) return 1000000;       // explicit 1M-context variant
  // Opus 4.x CAN run a 1M window, but only behind the context-1m beta; the id carries no
  // "1m" marker so we can't sense it. Defaulting opus-4 -> 1M would UNDER-read 5x for every
  // user on the standard 200k window and never trip the ceiling (the exact failure this
  // file warns against). So it's OPT-IN: a deployment that enabled the 1M beta sets
  // PHALANX_OPUS_1M=1 in its session/hook env. Default stays the safe 200k.
  if (process.env.PHALANX_OPUS_1M === "1" && /opus-4/.test(m)) return 1000000;
  // extend here for any model whose real window != 200k (keyed on the model id substring)
  return 200000;                                            // standard Claude window
}
const CEILING = 0.45;         // never exceed 45%
const WARN = 0.38;            // early nudge to start wrapping the current unit
const ONESHOT = process.env.PHALANX_ONESHOT === "1";

const readInput = H.readInput;
const emit = (ctx) => H.emit("PostToolUse", ctx);

// A supervisor (run-work.sh) IS an external fresh-process resumer: when one is
// driving, a ceiling hit must checkpoint + exit, NEVER tell a human to /clear.
const supervisorActive = H.supervisorActive;

// The last assistant turn's usage = the actual prompt size sent = context occupancy
// the gauge shows. Read a bounded tail (trailing tool_result lines can be large) and
// scan complete lines backward for the first message.usage. null when none found.
// ponytail: 1MB tail, not a full-file parse; null when no usage line is in the tail.
function lastUsage(tp, size) {
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
        if (t > 0) return { tokens: t, model: (rec.message.model || "") };
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

// Real usage signal only. No usage line yet (very early in a session) -> skip the
// nudge this turn rather than guess from raw bytes.
const usage = lastUsage(tp, bytes);
if (usage == null) emit("");
const real = usage.tokens;
const WINDOW_TOKENS = windowForModel(usage.model);  // sensed from the model on this turn
const frac = real / WINDOW_TOKENS;

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
  if (H.respawnPresent(H.readRepoFile(cwd, "PROGRESS.md"))) alreadyNudged = true;
  if (willResume) {
    const line = `\n<!-- RESPAWN ${new Date().toISOString()} ctx~${pct}% -- checkpoint state above, STOP, resume fresh -->\n`;
    try {
      if (!fs.existsSync(progress)) fs.writeFileSync(progress, "# PROGRESS\n");
      if (!H.respawnPresent(H.readRepoFile(cwd, "PROGRESS.md"))) fs.appendFileSync(progress, line);
    } catch {}
  }
  if (SUP) {
    // The supervisor relaunches a fresh `claude -p` pass that reads PROGRESS.md.
    emit(`CONTEXT CEILING HIT (~${pct}% >= 45%). Checkpoint remaining task state to PROGRESS.md NOW and STOP this pass -- the supervisor will relaunch a fresh pass that resumes from PROGRESS.md. No human action needed; do not tell anyone to reset context manually.`);
  }
  if (ONESHOT) {
    // A one-shot HOST (e.g. the Telegram bot) can still resume: it watches the agent's
    // final reply for the <<CONTINUE>> marker and hands the repo to a detached supervisor
    // that drives it to done/blocked across fresh passes (resuming from PROGRESS.md). So
    // do NOT dead-end the work -- checkpoint and signal continuation. (Still no RESPAWN
    // marker here: the supervisor resumes from the checkpoint content, and a bare one-shot
    // with no host that understands <<CONTINUE>> simply ends, same as before.)
    emit(`CONTEXT CEILING HIT (~${pct}% >= 45%) on a one-shot run. Checkpoint your remaining task state to PROGRESS.md NOW (enough for a fresh session to resume), do NOT start more work, and END your reply with the marker <<CONTINUE>> on its own line so the host hands the repo to a detached supervisor that finishes it across fresh passes.`);
  }
  // Bare interactive session: nudge to /clear ONCE (gated above); after that just
  // give the terse occupancy line so the instruction doesn't repeat every turn.
  if (alreadyNudged) {
    emit(`Context ~${pct}% (over 45% ceiling). Already checkpointed -- STOP and resume with /work in a fresh session.`);
  }
  emit(`CONTEXT CEILING HIT (~${pct}% >= 45%). Flush remaining task state to PROGRESS.md NOW, then STOP this session. Run /work in a fresh session to resume -- it reads PROGRESS.md first.`);
}

emit(`Context ~${pct}% — UNDER the 45% ceiling, headroom remains. KEEP WORKING: do NOT stop, and do NOT checkpoint-and-halt here. This is only a heads-up — wrap the CURRENT unit before opening a big NEW one, and prefer dispatching subagents over reading files yourself. ONLY a "CONTEXT CEILING HIT (>=45%)" message means stop; a WARN like this never does.`);
